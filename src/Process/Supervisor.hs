module Process.Supervisor where

import Control.Distributed.Process
import Control.Distributed.Process.Backend.SimpleLocalnet
import Control.Concurrent

import Data.Time.Clock.System
import Data.Maybe

import System.Random.MWC

import Process.Citizen (initCitizen)
import Process.Lookout (initLookout)
import Process.RNG (initRNG)

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




-- | Supervisor node - counts down the timers,
-- sends meta-commands and makes sure everything is running.
initSupervisor :: Double -- ^ Messaging time
               -> Double -- ^ Grace period
               -> Maybe GenIO -- ^ Seed, if supplied
               -> Backend
               -> Process ()
initSupervisor msg_dt grace_dt m_gen_io backend = do
    say "Supervisor: Spawned"
    pid <- getSelfPid
    lookout_pidref <- spawnLocalSupervised (initLookout backend)
    citizen_pidref <- spawnLocalSupervised  initCitizen
    m_rng_pidref   <- case m_gen_io of
        Just gen_io -> Just <$> spawnLocalSupervised (initRNG gen_io)
        Nothing     -> return Nothing
    -- Messaging period
    say "Supervisor: Starting messaging period"
    msg_start_t   <- liftIO $ getSystemTime
    msg_timer_pid <- spawnLocal $ timer (send pid =<< (TimerMsg <$> getSelfPid) ) msg_start_t msg_dt 
    messagingPeriod msg_timer_pid lookout_pidref citizen_pidref m_rng_pidref
    -- Grace period
    say "Supervisor: Starting grace period"
    grace_start_t    <- liftIO $ getSystemTime
    grace_timer_pid  <- spawnLocal $ timer (send pid =<< (TimerMsg <$> getSelfPid) ) grace_start_t grace_dt 
    citizen_finished <- gracePeriod grace_timer_pid citizen_pidref
    -- End
    if citizen_finished 
      then say "Supervisor: Citizen finished gracefully"
      else do 
           say "Supervisor: Citizen to be killed"
           unmonitor (snd citizen_pidref) 
           kill (fst citizen_pidref) "End of grace period" 
    liftIO $ threadDelay 250000

    
-- | Check whether all children are working - if not, restart.
messagingPeriod timer_pid lookout_pidref citizen_pidref m_rng_pidref = do
    todo <- receiveWait 
      [ matchIf (\(TimerMsg pid) -> pid == timer_pid) (\_ -> return 0)
      ]
    case todo of
        0 -> do
            let to_exit = catMaybes [Just lookout_pidref, m_rng_pidref] 
            mapM_ (\(pid,ref) -> unmonitor ref >> exit pid "Entering grace period") to_exit
            -- Request printing from citizen
            send (fst citizen_pidref) PrintMsg
        _ -> messagingPeriod timer_pid lookout_pidref citizen_pidref m_rng_pidref

-- | Check whenever citizen is working. Do not restart if failed. 
gracePeriod timer_pid citizen_pidref = do
    todo <- receiveWait 
      [ matchIf (\(TimerMsg pid) -> pid == timer_pid) (\_ -> return 0)
      , matchIf (\(ProcessMonitorNotification _ pid reason) -> pid == (fst citizen_pidref) && reason == DiedNormal) (\_ -> return 1)
      ]
    case todo of
        0 -> return False
        1 -> return True
        _ -> gracePeriod timer_pid citizen_pidref
