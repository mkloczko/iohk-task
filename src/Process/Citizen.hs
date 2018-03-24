module Process.Citizen where

import Control.Distributed.Process
import Data.Time.Clock.System

import Msg
import Scratchpad(show2Float)
data Chain = Chain [(Double, SystemTime)]
           deriving (Show)


-- | Propagates and sends messages further
initCitizen :: Process ()
initCitizen = do
    say "Citizen: Spawned"
    register "citizen" =<< getSelfPid
    nsend "lookout" =<< (RequestPrevious <$> liftIO getSystemTime <*> getSelfPid)
    loopCitizen (Chain [])



addNewMsg :: Chain
            -> (Double, SystemTime)
            -> Maybe Chain
addNewMsg (Chain lst) (d,t) = do
    -- Try to insert into the chain.
    -- If already in, there is no response.
    -- When an element is equal to another -> same 
    -- SEND HASHES!
    if (d,t) `elem` lst
        then Nothing
        else Just $ Chain ((d,t):lst)
    
mergeMsgs :: Chain 
          -> [(Double, SystemTime)]
          -> Chain
mergeMsgs chain []   = chain
mergeMsgs chain msgs = chain -- TODO

loopCitizen :: Chain -> Process ()
loopCitizen chain = do
    receiveWait (
      [ match (\(PropagateMsg n m t) -> do
          case addNewMsg chain (m,t) of 
              Just new_chain -> do
                say (concat ["Citizen: Msg ", show2Float m, " from ", show n, " - propagating"]) 
                nsend "lookout" (PropagateMsg n m t)      
                loopCitizen new_chain
              Nothing        -> do
                say (concat ["Citizen: Msg ", show2Float m, " from ", show n, " - already in"]) 
                loopCitizen     chain 
          )
      , match (\(PrintMsg            ) -> do
          say "Citizen: Received a print request" 
          loopCitizenGrace chain
          )
      , match (\(HiMsg pid) -> do 
          say ("Citizen: Discovered by " ++ show pid)
          usend pid =<< (ExistsMsg <$> getSelfPid)
          nsend "lookout" (HiMsg pid)
          loopCitizen chain
          )
      , match (\(ReconnectedMsg) -> do 
          say ("Citizen: Requesting previous messages")
          nsend "lookout" =<< (RequestPrevious <$> liftIO getSystemTime <*> getSelfPid)
          loopCitizen chain
          )
      , match (\(PreviousMsgs _ msgs pid) -> do 
          say (concat ["Citizen: Received previous msgs from ", show pid])
          nsend "lookout" =<< (RequestPrevious <$> liftIO getSystemTime <*> getSelfPid)
          loopCitizen chain
          )
      ])

-- | Entering grace period
loopCitizenGrace :: Chain -> Process ()
loopCitizenGrace chain = do 
    say "Citizen: Loop grace"
    smth <- receiveTimeout 50000 (
      [ match (\(PropagateMsg n m t) -> do
          case addNewMsg chain (m,t) of
            Just new_chain -> do
              say (concat ["Citizen: Msg ", show2Float m, " from ", show n, " - grace period"]) 
              loopCitizenGrace new_chain
            Nothing        -> do
              say (concat ["Citizen: Msg ", show2Float m, " from ", show n, " - grace period, alread in"]) 
              loopCitizenGrace     chain
          )
      ]) 
    case smth of 
        Nothing -> liftIO (putStrLn $ show chain)
        Just _  -> say "Citizen: This shouldn't happen"
