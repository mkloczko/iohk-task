{-#LANGUAGE DeriveGeneric #-}
{-#LANGUAGE DeriveAnyClass #-}
{-#LANGUAGE OverloadedStrings #-}
{-#LANGUAGE FlexibleInstances #-}
{-#LANGUAGE StandaloneDeriving #-}
module Msg where

import Control.Distributed.Process

import Crypto.Hash
import Crypto.Hash.Algorithms (SHA256)

import Data.Binary
import Data.ByteArray
import Data.ByteString (ByteString)
import Data.Time.Clock.System
import System.Random.MWC 

import GHC.Generics

import Scratchpad (show2Float, encodeDouble) -- import Binary SystemTime instance

data ExistsMsg = ExistsMsg  {-#UNPACK#-} !NodeId
                deriving (Generic, Binary, Show)
data HiMsg     = HiMsg      {-#UNPACK#-} !NodeId
                deriving (Generic, Binary, Show)


data RNGMsg = PropagateMsg {-#UNPACK#-}!NodeId {-#UNPACK#-}!Msg
            deriving (Generic, Binary, Show)

-- | Disconnected message
data DisconnectedMsg = DisconnectedMsg 
                       deriving (Generic,Binary,Show)

-- | Reconnected message
data ReconnectedMsg = ReconnectedMsg 
                       deriving (Generic,Binary,Show)
-- | Connected message
data ConnectedMsg = ConnectedMsg 
                       deriving (Generic,Binary,Show)
-- | Request all messages before
data RequestPrevious = RequestPrevious {-#UNPACK#-}!SystemTime {-#UNPACK#-}!ProcessId 
                        deriving (Generic, Binary, Show)

-- | Request between first system time and second system time
data RequestBetween  = RequestBetween {-#UNPACK #-}!SystemTime {-#UNPACK#-}!SystemTime {-#UNPACK#-}!ProcessId 
                        deriving (Generic, Binary, Show)

-- | Previous msgs, sent to be synchronised. Bool says whether it is the whole requested package.
data PreviousMsgs    = PreviousMsgs {-#UNPACK#-}!Bool [Msg] {-#UNPACK#-}!ProcessId
                        deriving (Generic, Binary, Show)


-- | Communicating that a process exited due to time running out. 
data TimerMsg = TimerMsg !ProcessId
                deriving(Generic, Binary)

data PrintMsg       = PrintMsg 
    deriving(Generic,Binary,Show)


-- | The message itself
data Msg = Msg {
      msgVal  :: {-#UNPACK#-}!Double
    , msgTime :: {-#UNPACK#-}!SystemTime
    , msgHash :: {-#UNPACK#-}!ByteString
} deriving (Eq, Ord, Generic, Binary)

instance Show Msg where
    show msg = show2Float $ msgVal msg


firstHashSeed :: ByteString
firstHashSeed = "i am first" :: ByteString

hasher :: (ByteArrayAccess a) => a -> Double -> ByteString
hasher bs d = convert (hash $ (bs `xor` encodeDouble d :: ByteString) :: Digest SHA256)

firstMsg :: GenIO -> IO Msg
firstMsg gen_io = do
    let init_bs = "i am first" :: ByteString
    t <- getSystemTime
    d <- uniform gen_io 
    return $ Msg d t (hasher init_bs d)

generateMsg :: GenIO -> Msg -> IO Msg
generateMsg gen_io msg = do
    t <- getSystemTime
    d <- uniform gen_io
    return $ Msg d t (hasher (msgHash msg) d)
    
