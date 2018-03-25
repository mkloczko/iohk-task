{-#LANGUAGE DeriveGeneric  #-}
{-#LANGUAGE DeriveAnyClass #-}
{-#LANGUAGE PatternGuards  #-}
module Process.Citizen where

import Control.Distributed.Process
import Data.Time.Clock.System
import           Data.Sequence (Seq, (<|), (|>), (><), ViewR(..), ViewL(..))
import qualified Data.Sequence as SQ
import           Data.Set      (Set)
import qualified Data.Set      as S

import Data.Binary
import Data.ByteString (ByteString)
import Data.Foldable
import Data.Maybe (fromJust)
import GHC.Generics

import Msg
import Scratchpad(show2Float)


-- | (Not too big) chain, defined as sequence of msgs.
-- Set of bytestrings says which hashes are in - assuming no collisions.
data Chain = Chain (Seq Msg) (Set ByteString)
    deriving (Eq)

instance Show Chain where
  show (Chain sq st) = concat [show sq, " ", show $ S.size st]

unsafeAddMsg :: Msg
             -> Chain
             -> Chain
unsafeAddMsg msg (Chain sq st) = Chain (msg <| sq) ((msgHash msg) `S.insert` st) 

unsafeMergeChains :: Chain
                  -> Msg
                  -> Chain
                  -> Chain
unsafeMergeChains (Chain sq1 st1) msg (Chain sq2 st2) = Chain (sq1 >< msg <| sq2) 
                                       (S.insert (msgHash msg) $ S.union st1 st2)

msgExists :: Msg   -- ^ Msg to check
          -> Chain -- ^ Chain
          -> Bool
msgExists msg (Chain sq st) = (msgHash msg) `S.member` st 
    
isMsgNext :: Msg        -- ^ Current msg
          -> ByteString -- ^ previous hash
          -> Bool
isMsgNext msg h = (msgHash msg) == (hasher h (msgVal msg))


data State = State
  { valid_chain     ::     Chain                
  , parts_of_chains :: Seq Chain -- ^ Parts of chains that are not validated
  } deriving (Show, Eq)

-- | Meta information for the algorithm
data WhichChain = Valid
                | NotValid Int
                | None
                deriving (Show, Eq)

mergeChains :: State 
            -> Msg
            -> WhichChain -- ^ Top chain
            -> WhichChain -- ^ Bottom chain
            -> Maybe State
mergeChains st                  msg None           None           = Nothing
mergeChains (State valid parts) msg Valid          None           = Just $ State (unsafeAddMsg msg valid) parts
mergeChains (State valid parts) msg None           (NotValid ix)  = Just $ State valid (SQ.adjust' (unsafeAddMsg msg) ix parts) 
mergeChains (State valid parts) msg Valid          (NotValid ix)  = Just $ State (unsafeMergeChains (SQ.index parts ix) msg valid) (SQ.deleteAt ix parts)
mergeChains (State valid parts) msg (NotValid ix1) (NotValid ix2) = Just $ State valid (SQ.deleteAt ix1 $ SQ.adjust' (unsafeMergeChains (SQ.index parts ix1) msg) ix2 parts )
mergeChains (State valid parts) msg _              (Valid)        = error "Valid chain cannot be glued from the bottom"
    
-- | Add a new message to the state
addMsgState :: Msg
            -> State
            -> Maybe State
addMsgState msg st@(State (Chain sq _) _)
   | EmptyL      <- SQ.viewl sq
   , isMsgNext msg firstHashSeed = mergeChains st msg Valid (seekStateBtm st msg)
   | otherwise = mergeChains st msg top btm
       where top = seekStateTop st msg  
             btm = seekStateBtm st msg

-- | Msg can be glued at top to which chain
seekStateTop :: State
             -> Msg
             -> WhichChain
seekStateTop (State valid parts) msg = do
    let m_ixs  = Nothing : map Just [0..]
        chs    = valid : toList parts
        whichs = zipWith (\ch m_ix -> msgChainTop ch msg m_ix) chs m_ixs
    maybe None id (find (/=None) whichs)

-- | Msg can be glued to bottom to which chain
seekStateBtm :: State
             -> Msg
             -> WhichChain
seekStateBtm (State valid parts) msg = do
    let ixs    = [0..]
        chs    = toList parts
        whichs = zipWith (\ch ix -> msgChainBtm ch msg ix) chs ixs
    maybe None id (find (/=None) whichs)

-- | Check whether the msgs adds to the top of the chain
msgChainTop :: Chain
            -> Msg
            -> Maybe Int -- ^ Whether is valid or non-valid chain
            -> WhichChain
msgChainTop (Chain sq st) msg m_ix
    | not $ S.member (msgHash msg) st
    , (m :< rst) <- SQ.viewl sq
    , isMsgNext msg (msgHash m) = case m_ix of
                          Just ix -> NotValid ix
                          Nothing -> Valid
    | otherwise = None

-- | Check whether the msg adds to the bottom of the non-valid chains 
msgChainBtm :: Chain
            -> Msg
            -> Int  -- ^ Non valid chain ix
            -> WhichChain
msgChainBtm (Chain sq st) msg ix
    | not $ S.member (msgHash msg) st
    , (rst :> m) <- SQ.viewr sq
    , isMsgNext m (msgHash msg) = NotValid ix
    | otherwise = None

    
    



-- | Propagates and sends messages further
initCitizen :: Process ()
initCitizen = do
    say "Citizen: Spawned"
    register "citizen" =<< getSelfPid
    nsend "lookout" =<< (RequestPrevious <$> liftIO getSystemTime <*> getSelfPid)
    loopCitizen (State (Chain SQ.empty S.empty) SQ.empty )


loopCitizen :: State -> Process ()
loopCitizen state = do
    receiveWait (
      [ match (\(PropagateMsg n m) -> do
          case addMsgState m state of 
            Just new_state -> do
              say (concat ["Citizen: Msg ", show2Float (msgVal m), " from ", show n, " - propagating"]) 
              nsend "lookout" (PropagateMsg n m)      
              loopCitizen new_state
            Nothing        -> do
              say (concat ["Citizen: Msg ", show2Float (msgVal m), " from ", show n, " - already in"]) 
              loopCitizen     state
          )
      , match (\(PrintMsg            ) -> do
          say "Citizen: Received a print request" 
          loopCitizenGrace state
          )
      , match (\(HiMsg pid) -> do 
          say (concat ["Citizen: Discovered by ", show pid])
          usend pid =<< (ExistsMsg <$> getSelfPid)
          nsend "lookout" (HiMsg pid)
          loopCitizen state
          )
      , match (\(ReconnectedMsg) -> do 
          say ("Citizen: Requesting previous messages")
          nsend "lookout" =<< (RequestPrevious <$> liftIO getSystemTime <*> getSelfPid)
          loopCitizen state
          )
      , match (\(PreviousMsgs _ msgs pid) -> do 
          say (concat ["Citizen: Received previous msgs from ", show pid])
          let new_state = foldl' (\s m -> maybe s id (addMsgState m s)) state msgs 
          loopCitizen new_state
          )
      ])

-- | Entering grace period
loopCitizenGrace :: State -> Process ()
loopCitizenGrace state = do 
    say "Citizen: Loop grace"
    smth <- receiveTimeout 50000 (
      [ match (\(PropagateMsg n m) -> do
          case addMsgState m state of
            Just new_state -> do
              say (concat ["Citizen: Msg ", show2Float (msgVal m), " from ", show n, " - grace period"]) 
              loopCitizenGrace new_state
            Nothing        -> do
              say (concat ["Citizen: Msg ", show2Float (msgVal m), " from ", show n, " - grace period, already in"]) 
              loopCitizenGrace     state
          )
      , match (\(PreviousMsgs _ msgs pid) -> do 
          say (concat ["Citizen: Received previous msgs from ", show pid, " - grace period"])
          let new_state = foldl' (\s m -> maybe s id (addMsgState m s)) state msgs 
          loopCitizen new_state
          )
      ]) 
    case smth of 
        Nothing -> liftIO $ printTask state
        Just _  -> say "Citizen: This shouldn't happen"


-- | Printing the task result.
printTask :: State -> IO ()
printTask (State (Chain sq st) _) = print (size, the_sum)
  where the_sum = foldl' (\s (val, ix) -> s + ix*val) 0 $ zip (reverse $ map msgVal (toList sq)) [1..]
        size    = SQ.length sq
