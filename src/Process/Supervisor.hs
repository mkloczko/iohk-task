module Process.Supervisor where

import Control.Distributed.Process
import Control.Distributed.Process.Backend.SimpleLocalnet
import Control.Concurrent
import Crypto.Hash 

import Data.ByteString.Char8 (pack, unpack)
import Data.ByteArray (convert)
import Data.Time.Clock.System
import Data.Maybe

import System.Random.MWC

import Process.Citizen (initCitizen)
import Process.Lookout (initLookout)
import Process.RNG (initRNG)

import System.Directory


import Msg
import Scratchpad (diffSysTime)

-- | Spawns a process, links a child to parent, parent monitors the child.
spawnLocalSupervised :: Process () -> Process (ProcessId, MonitorRef)
spawnLocalSupervised p = do
    supervisor_pid <- getSelfPid
    child_pid      <- spawnLocal (link supervisor_pid >> p)
    monitor_ref    <- monitor child_pid
    return (child_pid, monitor_ref)

-- | Timer process behaviour
timer :: Process () -- ^ What to do when time runs out.
      -> SystemTime -- ^ Start time
      -> Double     -- ^ Delta time
      -> Process ()
timer todo start_t dt = do
    liftIO$ threadDelay 250000
    end_t <- liftIO $ getSystemTime
    if diffSysTime end_t start_t > dt
        then todo
        else timer todo start_t dt


data SupervisorKit = SupervisorKit 
  { rng_interval :: Word
  , m_gen        :: Maybe GenIO
  , backend_kit  :: Backend
  , fname_cit    :: String
  } 


-- | Supervisor node - counts down the timers,
-- sends meta-commands and makes sure everything is running.
initSupervisor :: Double -- ^ Messaging time
               -> Double -- ^ Grace period
               -> Word   -- ^ RNG interval time
               -> Maybe GenIO -- ^ Seed, if supplied
               -> Backend
               -> Process ()
initSupervisor msg_dt grace_dt rng_inter m_gen_io backend = do
    nid <- getSelfNode
    let fname_citizen = (unpack.convert) $ ((hash.pack) $ concat [show nid, ":citizen"] :: Digest SHA256)
        kit           = SupervisorKit rng_inter m_gen_io backend fname_citizen
    say "Supervisor: Spawned"
    pid <- getSelfPid

    --Touch a file
    liftIO $ writeFile fname_citizen ""
    
    lookout_pidref <- spawnLocalSupervised (initLookout backend)
    citizen_pidref <- spawnLocalSupervised $ initCitizen fname_citizen
    m_rng_pidref   <- case m_gen_io of
        Just gen_io -> Just <$> spawnLocalSupervised (initRNG gen_io rng_inter)
        Nothing     -> return Nothing
    -- Messaging period
    say "Supervisor: Starting messaging period"
    msg_start_t   <- liftIO $ getSystemTime
    msg_timer_pid <- spawnLocal $ timer (send pid =<< (TimerMsg <$> getSelfPid) ) msg_start_t msg_dt 
    messagingPeriod kit msg_timer_pid lookout_pidref citizen_pidref m_rng_pidref
    -- Grace period
    say "Supervisor: Starting grace period"
    grace_start_t    <- liftIO $ getSystemTime
    grace_timer_pid  <- spawnLocal $ timer (send pid =<< (TimerMsg <$> getSelfPid) ) grace_start_t grace_dt 
    citizen_finished <- gracePeriod kit grace_timer_pid citizen_pidref
    -- End
    if citizen_finished 
      then say "Supervisor: Citizen finished gracefully"
      else do 
           say "Supervisor: Citizen to be killed"
           unmonitor (snd citizen_pidref) 
           kill (fst citizen_pidref) "End of grace period" 
    liftIO $ threadDelay 250000
    liftIO $ removeFile fname_citizen

    
-- | Check whether all children are working - if not, restart.
messagingPeriod kit timer_pid lookout_pidref citizen_pidref m_rng_pidref = do
    todo <- receiveWait 
      [ matchIf (\(TimerMsg pid) -> pid == timer_pid) (\_ -> return 0)
      , match   (\(ProcessMonitorNotification ref pid rsn) -> do
          let is_lookout = (pid == fst lookout_pidref)
              is_citizen = (pid == fst citizen_pidref)
              m_is_rng   = (pid ==).fst <$> m_rng_pidref
          case (is_lookout, is_citizen, m_is_rng) of
              (True,_,_)      -> (say.concat) ["Supervisor: Lookout died - ", show rsn] >> return 1
              (_,True,_)      -> (say.concat) ["Supervisor: Citizen died - ", show rsn] >> return 2
              (_,_,Just True) -> (say.concat) ["Supervisor: RNG died - "    , show rsn] >> return 3
              _               -> (say.concat) ["Supervisor: Unknown process died"]      >> return (-1)
        )
      ]
    case todo of
        0 -> do
            let to_exit = catMaybes [Just lookout_pidref, m_rng_pidref] 
            mapM_ (\(pid,ref) -> unmonitor ref >> exit pid "Entering grace period") to_exit
            -- Request printing from citizen
            send (fst citizen_pidref) PrintMsg
        1 -> do
          new_lookout <- spawnLocalSupervised (initLookout $ backend_kit kit)
          messagingPeriod kit timer_pid new_lookout citizen_pidref m_rng_pidref
        2 -> do
          new_citizen <- spawnLocalSupervised (initCitizen $ fname_cit kit)
          messagingPeriod kit timer_pid lookout_pidref new_citizen m_rng_pidref
        3 -> do
          new_rng <- case m_gen kit of 
            Just gen -> Just <$> spawnLocalSupervised (initRNG gen (rng_interval kit))
            Nothing  -> say "Supervisor: Could not respawn RNG process due to lack of rng generator." 
                      >> return Nothing 
          messagingPeriod kit timer_pid lookout_pidref citizen_pidref new_rng
        _ -> messagingPeriod kit timer_pid lookout_pidref citizen_pidref m_rng_pidref

-- | Check whenever citizen is working. Do not restart if failed. 
gracePeriod kit timer_pid citizen_pidref = do
    todo <- receiveWait 
      [ matchIf (\(TimerMsg pid) -> pid == timer_pid) (\_ -> return 0)
      , matchIf (\(ProcessMonitorNotification _ pid reason) -> pid == (fst citizen_pidref)) (\not -> do
          let (ProcessMonitorNotification r p rsn) = not
          case rsn of
              DiedNormal -> return 1
              _          -> (say.concat) ["Supervisor: Citizen died during grace period ", show rsn] >> return 2
        )
      ]
    case todo of
        0 -> return False
        1 -> return True
        2 -> do
          new_citizen <- spawnLocalSupervised (initCitizen $ fname_cit kit)
          gracePeriod kit timer_pid new_citizen
        _ -> gracePeriod kit timer_pid citizen_pidref
