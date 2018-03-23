module Process.Citizen where

import Control.Distributed.Process
import Data.Time.Clock.System

import Msg

data Chain = Chain [(Double, SystemTime)]
           deriving (Show)

data Response = PropMessage NodeId Double SystemTime
              | Print 
              | Exit
              | None
              deriving (Show)

-- | Propagates and sends messages further
initCitizen :: Process ()
initCitizen = do
    say "Citizen: Spawned"
    register "citizen" =<< getSelfPid
    loopCitizen (Chain [])
    -- chain <- requestData

chainNewMsg :: Chain
            -> (NodeId, Double, SystemTime)
            -> Process (Chain, Response)
chainNewMsg (Chain lst) (n,d,t) = do
    -- Try to insert into the chain.
    -- If already in, there is no response.
    -- When an alement is equal to another -> same 
    -- SEND HASHES!
    if (d,t) `elem` lst
        then return (Chain        lst , None)
        else return (Chain ((d,t):lst), PropMessage n d t)
    

loopCitizen :: Chain -> Process ()
loopCitizen chain = do
    (new_chain, response) <- receiveWait (
      [ match (\(FromLookoutMsg n m t) -> say ("Citizen: Received a message from lookout " ++ show m) >> chainNewMsg chain (n,m,t) )
      , match (\(PrintMsg            ) -> say "Citizen: Received a print request" >> return (chain, Print)     )
      ])
    case response of 
        PropMessage n m t -> nsend "lookout" (ToLookoutMsg n m t) >> loopCitizen new_chain
        Print             -> liftIO $ putStrLn (show chain) 
        None              -> loopCitizen new_chain

