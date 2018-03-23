{-#LANGUAGE DeriveGeneric #-}
{-#LANGUAGE DeriveAnyClass #-}

module Msg where

import Control.Distributed.Process

import Crypto.Hash
import Crypto.Hash.Algorithms (SHA256)

import Data.Binary
import Data.Time.Clock.System

import GHC.Generics

instance Binary SystemTime where
    put (MkSystemTime secs nsecs) = put secs >> put nsecs
    get = MkSystemTime <$> get <*> get

data ExistsMsg = ExistsMsg  {-#UNPACK#-} !ProcessId
                deriving (Generic, Binary, Show)
data HiMsg     = HiMsg      {-#UNPACK#-} !ProcessId
                deriving (Generic, Binary, Show)


data RNGMsg = PropagateMsg {-#UNPACK#-}!NodeId {-#UNPACK#-}!Double {-#UNPACK#-}!SystemTime 
            deriving (Generic, Binary, Show)

data ToLookoutMsg   = ToLookoutMsg   NodeId Double SystemTime
                       deriving (Generic, Binary, Show)
data FromLookoutMsg = FromLookoutMsg NodeId Double SystemTime
                       deriving (Generic, Binary, Show)

-- | Communicating that a process exited due to time running out. 
data TimerMsg = TimerMsg !ProcessId
                deriving(Generic, Binary)

data PrintMsg       = PrintMsg 
    deriving(Generic,Binary,Show)

data Msg = Msg {
      val  :: Double
    , time :: SystemTime
    , hash :: Digest SHA256
} deriving (Show, Eq, Ord)
