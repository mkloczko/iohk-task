{-#LANGUAGE TupleSections #-}
module Process.Lookout where

import Control.Distributed.Process
import Control.Distributed.Process.Backend.SimpleLocalnet
import Control.Monad
import           Data.Map (Map)
import qualified Data.Map as M
import Data.Time.Clock.System

import Data.List
import Data.Maybe
import Msg
import Scratchpad(show2Float)

type NeighbourMap = Map ProcessId MonitorRef  

-- | Look for other nodes at start
sayHi :: Backend -> Process NeighbourMap 
sayHi backend = do
    nodes <- liftIO $ findPeers backend 300000
    this_node <- getSelfNode
    let other_nodes = nodes \\ [this_node]
    bracket (mapM monitorNode other_nodes) (mapM unmonitor) $ \_ -> do
        my_pid <- getSelfPid
        mapM (\n -> nsendRemote n "citizen" (HiMsg my_pid) ) other_nodes
        M.fromList <$> catMaybes <$> catMaybes <$> replicateM (length other_nodes) (
          receiveTimeout 100000
            [ match (\(ExistsMsg pid) -> Just <$> ((pid,) <$> monitor pid))
            , match (\(NodeMonitorNotification {}) -> return $ Nothing)
            ])

-- | Process functionality related to looking for other nodes.
initLookout :: Backend -> Process ()
initLookout backend = do
    say "Lookout: Spawned"
    register "lookout" =<< getSelfPid
    other_lookouts <- sayHi backend
    lookoutLoop backend (M.empty /= other_lookouts) other_lookouts


lookoutLoop :: Backend 
            -> Bool    -- ^ Was connected in last iteration ?
            -> NeighbourMap
            -> Process () 
-- When disconnecting, do not inform the citizen about it, for now.
lookoutLoop backend was_connected nbs
    | M.size nbs == 0 = lookoutLoop backend False =<< lookoutLoopDisconnected backend -- Was empty, disconnected behaviour
    | was_connected   = lookoutLoop backend True  =<< lookoutLoopConnected    nbs     -- Was connected and still is
    | otherwise       = do                                                            -- Was disconnected and is connected
        --Send message that we were disconnected to the citizen.
        nsend "citizen" ReconnectedMsg 
        lookoutLoop backend True  =<< lookoutLoopConnected nbs

checkIfLocal :: ProcessId
             -> Process Bool
checkIfLocal pid = (== processNodeId pid) <$> getSelfNode

lookoutLoopConnected :: NeighbourMap         -- ^ Current neighbours 
                     -> Process NeighbourMap 
lookoutLoopConnected others = do
    new_others <- receiveWait (
      -- Peer discovery messages
      [ match (\(ExistsMsg pid) -> do
          is_local <- checkIfLocal pid
          if is_local
            then return others
            else do
              say $ concat ["Lookout: Found citizen at ", show pid]
              M.insert pid <$> monitor pid <*> pure others
          )
      , match (\(HiMsg pid) -> do
          is_local <- checkIfLocal pid
          if is_local
            then return others
            else do
              my_pid <- getSelfPid
              nsendRemote (processNodeId pid) "citizen" (HiMsg pid)
              return others
          )
      -- Task messages
      , match (\(PropagateMsg n m t) -> do
          propagate (M.keys others) (n,m,t) =<< getSelfNode
          return others
          )
      -- Monitors
      , match (\(ProcessMonitorNotification ref pid _) -> do
          say $ concat ["Lookout: ", show pid, " disconnected"]
          return $ M.delete pid others
          )
      ])
    return new_others

lookoutLoopDisconnected :: Backend -> Process NeighbourMap
lookoutLoopDisconnected backend = sayHi backend
    

propagate :: [ProcessId]
          -> (NodeId, Double, SystemTime) -- ^ Data from the other msg
          -> NodeId                       -- ^ Local node 
          -> Process ()
propagate others (n, d, t) my_n = mapM_ sender $ filter (\p -> processNodeId p /= n) others
   where sender pid = do
           say (concat ["Lookout: Sending ", show2Float d," from ", show n," to ", show pid])
           usend pid (PropagateMsg my_n d t)

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
