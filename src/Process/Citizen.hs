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
import qualified Data.ByteString as B
import Data.Foldable
import Data.Maybe (fromJust)
import Control.Exception (try)
import GHC.Generics

import Msg
import Scratchpad(show2Float)


-- | (Not too big) chain, defined as sequence of msgs.
-- Set of bytestrings says which hashes are in - assuming no collisions.
data Chain = Chain (Seq Msg) (Set ByteString)
    deriving (Eq, Generic, Binary)

instance Show Chain where
  show (Chain sq st) = concat [show sq, " ", show $ S.size st]

unsafeAddMsgTop :: Msg
             -> Chain
             -> Chain
unsafeAddMsgTop msg (Chain sq st) = Chain (msg <| sq) ((msgHash msg) `S.insert` st) 

unsafeAddMsgBtm :: Msg
             -> Chain
             -> Chain
unsafeAddMsgBtm msg (Chain sq st) = Chain (sq |> msg) ((msgHash msg) `S.insert` st) 

unsafeMergeChains :: Chain
                  -> Msg
                  -> Chain
                  -> Chain
unsafeMergeChains (Chain sq1 st1) msg (Chain sq2 st2) = Chain (sq1 >< msg <| sq2) 
                                       (S.insert (msgHash msg) $ S.union st1 st2)

newChain :: Msg
         -> Chain
newChain msg@(Msg v t h) = Chain (SQ.singleton msg) (S.singleton h)

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
  } deriving (Show, Eq, Generic, Binary)

lastValidMsgTime :: State
                 -> Maybe SystemTime
lastValidMsgTime (State (Chain msgs _) _) 
    | EmptyL     <- SQ.viewl msgs 
    = Nothing
    | ((Msg _ t _) :< rst) <- SQ.viewl msgs 
    = Just t


-- | Meta information for the algorithm
data WhichChain = Valid
                | NotValid Int
                | None
                | New
                deriving (Show, Eq)

mergeChains :: State 
            -> Msg
            -> WhichChain -- ^ Top chain
            -> WhichChain -- ^ Bottom chain
            -> Maybe State
mergeChains st                  msg None           None           = Nothing
mergeChains st                  msg None           New            = Nothing
mergeChains (State valid parts) msg New            New            = Just $ State valid (newChain msg <| parts)
mergeChains (State valid parts) msg Valid          (NotValid ix)  = Just $ State (unsafeMergeChains (SQ.index parts ix) msg valid) (SQ.deleteAt ix parts)
mergeChains (State valid parts) msg (NotValid ix1) (NotValid ix2) = Just $ State valid (SQ.deleteAt ix2 $ SQ.adjust' (unsafeMergeChains (SQ.index parts ix2) msg) ix1 parts )
mergeChains (State valid parts) msg Valid          None           = Just $ State (unsafeAddMsgTop msg valid) parts
mergeChains (State valid parts) msg Valid          New            = Just $ State (unsafeAddMsgTop msg valid) parts
mergeChains (State valid parts) msg _              (NotValid ix)  = Just $ State valid (SQ.adjust' (unsafeAddMsgBtm msg) ix parts) 
mergeChains (State valid parts) msg (NotValid ix)  _              = Just $ State valid (SQ.adjust' (unsafeAddMsgTop msg) ix parts) 
mergeChains (State valid parts) msg _              (Valid)        = error "mergeChains: Valid chain cannot be glued from the bottom"
mergeChains (State valid parts) msg a              b              = error $ concat ["mergeChains: Unsupported case. ", show a, " ", show b]    
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
    case filter (/= None) whichs of
        [] -> None
        ls -> maybe New id (find (/=New) ls) 


-- | Msg can be glued to bottom to which chain
seekStateBtm :: State
             -> Msg
             -> WhichChain
seekStateBtm (State valid parts) msg = do
    let ixs    = [0..]
        chs    = toList parts
        whichs = zipWith (\ch ix -> msgChainBtm ch msg ix) chs ixs
    case filter (/= None) whichs of
        [] -> case whichs of
          [] -> New
          _  -> None
        ls -> maybe New id (find (/=New) ls) 

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
    | not $ S.member (msgHash msg) st = New
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
    | not $ S.member (msgHash msg) st = New
    | otherwise = None

    
    

saveCitizen :: String -> State -> IO ()
saveCitizen str st = encodeFile str st

loadCitizen :: String -> IO (Maybe State)
loadCitizen str = do
  e_state <- decodeFileOrFail str
  case e_state of
      Left err -> return Nothing
      Right st -> return $ Just st

-- | Propagates and sends messages further
initCitizen :: String -> Process ()
initCitizen fname = do
    say "Citizen: Spawned"
    pid <- getSelfPid
    nid <- getSelfNode
    register "citizen" pid

    m_st <- liftIO $ loadCitizen fname
    case m_st of 
      Nothing -> do
        say "Citizen: Starting with new state"
        say "Citizen: Requesting previous messages"
        nsend "lookout" =<< (RequestPrevious <$> liftIO getSystemTime <*> getSelfPid)
        loopCitizen fname (State (Chain SQ.empty S.empty) SQ.empty )
      Just st -> do
        say "Citizen: Loaded previous state"
        say "Citizen: Requesting previous messages"
        t_to   <- liftIO $ getSystemTime 
        case lastValidMsgTime st of
          Just t_from -> nsend "lookout" $ RequestBetween  t_from t_to pid
          Nothing     -> nsend "lookout" $ RequestPrevious        t_to pid
        loopCitizen fname st


loopCitizen :: String -> State -> Process ()
loopCitizen fname state = do
    receiveWait (
      [ match (\(PropagateMsg n m) -> do
          case addMsgState m state of 
            Just new_state -> do
              say (concat ["Citizen: Msg ", show2Float (msgVal m), " from ", show n, " - propagating"]) 
              nsend "lookout" (PropagateMsg n m) 
              liftIO $ saveCitizen fname new_state
              loopCitizen fname new_state
            Nothing        -> do
              say (concat ["Citizen: Msg ", show2Float (msgVal m), " from ", show n, " - already in"]) 
              loopCitizen fname state
          )
      , match (\(PrintMsg            ) -> do
          say "Citizen: Received a print request" 
          loopCitizenGrace fname state
          )
      , match (\(HiMsg nid) -> do 
          say (concat ["Citizen: Discovered by ", show nid])
          nsend "lookout" (HiMsg nid)
          loopCitizen fname state
          )
      , match (\(ReconnectedMsg) -> do 
          say ("Citizen: Requesting previous messages")
          t_to   <- liftIO $ getSystemTime 
          my_pid <- getSelfPid 
          case lastValidMsgTime state of
            Just t_from -> nsend "lookout" $ RequestBetween  t_from t_to my_pid
            Nothing     -> nsend "lookout" $ RequestPrevious        t_to my_pid
          loopCitizen fname state
          )
      , match (\(PreviousMsgs all msgs pid) -> do 
          say (concat ["Citizen: Received previous msgs from ", show pid])
          let new_state = foldl' (\s m -> maybe s id (addMsgState m s)) state msgs 
          if all 
             then return ()
             else do 
               t_to   <- liftIO $ getSystemTime
               my_pid <- getSelfPid
               case lastValidMsgTime new_state of
                 Just t_from -> nsend "lookout" $ RequestBetween  t_from t_to my_pid
                 Nothing     -> nsend "lookout" $ RequestPrevious        t_to my_pid
          liftIO $ saveCitizen fname new_state
          loopCitizen fname new_state
          )
      ])


-- | Entering grace period
loopCitizenGrace :: String -> State -> Process ()
loopCitizenGrace fname state = do 
    smth <- receiveTimeout 50000 (
      [ match (\(PropagateMsg n m) -> do
          case addMsgState m state of
            Just new_state -> do
              say (concat ["Citizen: Msg ", show2Float (msgVal m), " from ", show n, " - grace period"]) 
              liftIO $ saveCitizen fname new_state
              loopCitizenGrace fname new_state
            Nothing        -> do
              say (concat ["Citizen: Msg ", show2Float (msgVal m), " from ", show n, " - grace period, already in"]) 
              loopCitizenGrace fname     state
          )
      , match (\(PreviousMsgs _ msgs pid) -> do 
          say (concat ["Citizen: Received previous msgs from ", show pid, " - grace period"])
          let new_state = foldl' (\s m -> maybe s id (addMsgState m s)) state msgs 
          liftIO $ saveCitizen fname new_state
          loopCitizenGrace fname new_state
          )
      ]) 
    case smth of 
        Nothing -> printTask state
        Just _  -> return () -- Shouldn't happen because we are supposed to loop until there are no messages


-- | Printing the task result.
showTask :: State -> String
showTask (State (Chain sq st) _) = show (size, the_sum)
  where the_sum = foldl' (\s (val, ix) -> s + ix*val) 0 $ zip (reverse $ map msgVal (toList sq)) [1..]
        size    = SQ.length sq

printTask :: State -> Process ()
printTask state = do 
   nid <- getSelfNode
   liftIO $ putStrLn $ concat [show nid,": " ,showTask state]
