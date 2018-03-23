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

-- | Look for other nodes at start
sayHi :: Backend -> Process [(ProcessId, MonitorRef)] 
sayHi backend = do
    nodes <- liftIO $ findPeers backend 300000
    this_node <- getSelfNode
    bracket (mapM monitorNode (nodes \\ [this_node])) (mapM unmonitor) $ \_ -> do
        my_pid <- getSelfPid
        mapM (\n -> nsendRemote n "lookout" (HiMsg my_pid) ) nodes
        catMaybes <$> catMaybes <$> replicateM (length nodes) (
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
    lookoutLoop other_lookouts


lookoutLoop :: [(ProcessId,MonitorRef)]  -- ^ Current neighbours 
            -> Process ()
lookoutLoop others = do
    new_others <- receiveWait (
      -- Peer discovery messages
      [ match (\(HiMsg pid)     -> do
          send pid =<< (ExistsMsg <$> getSelfPid)
          (:) <$> ((pid,) <$> monitor pid ) <*> pure others)
      , match (\(ExistsMsg pid) -> do
          (:) <$> ((pid,) <$> monitor pid ) <*> pure others)
      -- Random number handling
      , match (\(PropagateMsg n m t) -> do
          say "Lookout: Received a msg to propagate"
          nsend     "citizen" (FromLookoutMsg n m t)
          return others)
      , match (\(ToLookoutMsg n m t) -> do
          say "Lookout: Received a msg from local citizen"
          propagate (map fst others) (n,m,t) =<< getSelfNode
          return others)
      -- Monitors
      , match (\(ProcessMonitorNotification ref pid _) -> return $ others \\ [(pid,ref)])
      ])
    lookoutLoop new_others

propagate :: [ProcessId]
          -> (NodeId, Double, SystemTime) -- ^ Data from the other msg
          -> NodeId                       -- ^ My node 
          -> Process ()
propagate others (n, d, t) my_n = do
    mapM_ (\p -> send p (PropagateMsg my_n d t)) $ filter (\p -> processNodeId p /= n) others

