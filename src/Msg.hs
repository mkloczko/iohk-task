{-#LANGUAGE DeriveGeneric #-}
{-#LANGUAGE DeriveAnyClass #-}

module Msg where

import Control.Distributed.Process

import Crypto.Hash
import Crypto.Hash.Algorithms (SHA256)

import Data.Binary
import Data.Time.Clock.System

import GHC.Generics
import Scratchpad () -- import Binary SystemTime instance

data ExistsMsg = ExistsMsg  {-#UNPACK#-} !ProcessId
                deriving (Generic, Binary, Show)
data HiMsg     = HiMsg      {-#UNPACK#-} !ProcessId
                deriving (Generic, Binary, Show)


data RNGMsg = PropagateMsg {-#UNPACK#-}!NodeId {-#UNPACK#-}!Double {-#UNPACK#-}!SystemTime 
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
data PreviousMsgs    = PreviousMsgs {-#UNPACK#-}!Bool [(Double, SystemTime)] {-#UNPACK#-}!ProcessId
                        deriving (Generic, Binary, Show)


-- | Communicating that a process exited due to time running out. 
data TimerMsg = TimerMsg !ProcessId
                deriving(Generic, Binary)

data PrintMsg       = PrintMsg 
    deriving(Generic,Binary,Show)

data Msg = Msg {
      val  :: Double
    , time :: SystemTime
--    , hash :: Digest SHA256
} deriving (Show, Eq, Ord)
