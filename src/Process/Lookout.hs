{-#LANGUAGE TupleSections #-}
module Process.Lookout where

import Control.Distributed.Process
import Control.Distributed.Process.Backend.SimpleLocalnet
import Control.Monad
import           Data.Map (Map)
import qualified Data.Map as M

import Data.Binary 
import Data.Time.Clock.System
import Data.List
import Data.Maybe
import Data.Typeable

import Msg
import Scratchpad(show2Float)

type NeighbourMap = Map NodeId MonitorRef  


for2M as bs f = zipWithM f as bs

-- | Look for other nodes at start
sayHi :: Backend -> Process NeighbourMap 
sayHi backend = do
    nodes <- liftIO $ findPeers backend 300000
    this_node <- getSelfNode
    let other_nodes = nodes \\ [this_node] 
    refs <- mapM monitorNode other_nodes
    say $ concat ["Lookout: Searching for other lookouts at ", show other_nodes]
    M.fromList <$> catMaybes <$> catMaybes <$> for2M other_nodes refs (\n r -> do
        nsendRemote n "lookout" (HiMsg this_node)
        receiveTimeout 100000
          [ match (\(ExistsMsg nid) -> return $ Just (nid,r) )
          , match (\(NodeMonitorNotification {}) -> say "bye" >> return Nothing)
          ]
        )

-- | Process functionality related to looking for other nodes.
initLookout :: Backend -> Process ()
initLookout backend = do
    say "Lookout: Spawned"
    register "lookout" =<< getSelfPid
    other_lookouts <- sayHi backend
    if M.size other_lookouts == 0
      then say           "Lookout: Starting at disconnected state"
      else say $ concat ["Lookout: Connected to ", show $ M.size other_lookouts , " node(s)"]
    lookoutLoop backend (M.empty /= other_lookouts) other_lookouts


lookoutLoop :: Backend 
            -> Bool    -- ^ Was connected in last iteration ?
            -> NeighbourMap
            -> Process () 
-- When disconnecting, do not inform the citizen about it, for now.
lookoutLoop backend was_connected nbs
    | M.size nbs == 0
    , was_connected   = do
        say "Lookout: Disconnected"
        lookoutLoop backend False =<< lookoutLoopDisconnected backend                 -- Was connected, disconnected behaviour
    | M.size nbs == 0 = lookoutLoop backend False =<< lookoutLoopDisconnected backend -- Was disconnected and still is
    | was_connected   = lookoutLoop backend True  =<< lookoutLoopConnected    nbs     -- Was connected and still is
    | otherwise       = do                                                            -- Was disconnected, connected behaviour
        --Send message that we were disconnected to the citizen.
        say "Lookout: Reconnected"
        nsend "citizen" ReconnectedMsg 
        lookoutLoop backend True  =<< lookoutLoopConnected nbs

checkIfLocal :: NodeId
             -> Process Bool
checkIfLocal nid = (== nid) <$> getSelfNode

lookoutLoopConnected :: NeighbourMap         -- ^ Current neighbours 
                     -> Process NeighbourMap 
lookoutLoopConnected others = do
    new_others <- receiveWait (
      -- Peer discovery messages
      [ match (\(ExistsMsg nid) -> do
          is_local <- checkIfLocal nid
          if is_local
            then return others
            else do
              say $ concat ["Lookout: Found node at ", show nid]
              M.insert nid <$> monitorNode nid <*> pure others
          )
      , match (\(HiMsg nid) -> do
          my_nid <- getSelfNode
          nsendRemote nid "lookout" (ExistsMsg my_nid)
          is_local <- checkIfLocal nid
          if is_local || M.member nid others
            then return others
            else do
              nsendRemote nid "lookout" (HiMsg my_nid)
              return others
          )
      -- Task messages
      , match (\(PropagateMsg n m@(Msg v _ _)) -> do
          let logsay = concat ["Sending message ", show2Float v ]
          my_nid <- getSelfNode
          propagate (PropagateMsg my_nid m) logsay (filter (/=n) $ M.keys others) "citizen"
          return others
          )
      -- Monitors
      , match (\(NodeMonitorNotification ref nid rsn) ->  do
          say $ concat ["Lookout: ", show nid, " disconnected. ", show rsn]
          return $ M.delete nid others
          )
      ])
    return new_others




lookoutLoopDisconnected :: Backend -> Process NeighbourMap
lookoutLoopDisconnected backend = do 
    m_other <- receiveTimeout 100000 
      [ match (\(ExistsMsg nid) -> do
          is_local <- checkIfLocal nid
          if is_local
            then lookoutLoopDisconnected backend
            else do
              say $ concat ["Lookout: Found node at ", show nid]
              M.singleton nid <$> monitorNode nid
          )
      , match (\(HiMsg nid) -> do
          my_nid <- getSelfNode
          nsendRemote nid "lookout" (ExistsMsg my_nid)
          is_local <- checkIfLocal nid
          if is_local 
            then lookoutLoopDisconnected backend 
            else do
              nsendRemote nid "lookout" (HiMsg my_nid)
              lookoutLoopDisconnected backend
          )
       ]
    case m_other of
      Just smth -> return smth
      Nothing -> sayHi backend
    

-- | Propagate messages
propagate :: (Typeable a, Binary a)
          => a        -- ^ Message
          -> String   -- ^ To log
          -> [NodeId] -- ^ Processes to send to
          -> String   -- ^ Which process
          -> Process ()
propagate m logsay others p_name= mapM_ sender others
   where sender nid = say (concat ["Lookout: ", logsay ," to ", p_name, " at ", show nid]) >> nsendRemote nid p_name m

-- [Monitoring other processes]
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- 
-- Lookout monitors other (citizen) processes.
-- If disconnected (every other node went down), do something ?...
--
-- How to differentiate between single node and disconnected node ? (No need to, actually)
-- Having msgs to propagate - while disconnected, do we hold them ?
--
-- Propagating after disconnection vs requesting information after disconnection.
-- Choose latter ?
--
-- While disconnected (no other nodes) -> lookout looks for other nodes,
-- citizen sleeps ?
--
-- citizen Disconnect to connected -> request messages between last msg to current time
-- 
-- Two lookout loops - one for single-node state, other for multiple-nodes state.
-- Single node state - look for other nodes, handle Hi's, do not propagate any messages
-- Multi-node state  - handle Hi's from other nodes, propagate msgs
--
-- Citizen loops:
-- Single node state - disconnected, process msgs (most likely from rng or some lost in the buffer)
-- Switch from disconnected to connected -> request changes (how many, from each node?), after that resume loop
-- Multi-node  state - connected, process msgs
-- Switch from connected to disconnected -> do nothing, just go
--
-- Requesting changes is the most problematic here. Lookout knows other nodes, citizen does not. 
-- Citizen propagates msg to lookout, and citizen waits for responses - how many will he receive ? 
-- He should receive all.
-- Should he wait for all ?
-- New msgs should be storred in a different state
-- Request in intervals (message spam?), until the spots are filled.
--
-- Hashes can be used to 
--
-- Citizen spawns another process which collects msgs up till certain time ?
--
-- Collisions between messages... ok, that will be dealt later on. For now one honest generator 
