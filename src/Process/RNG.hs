{-#LANGUAGE RecordWildCards#-}
{-#LANGUAGE TupleSections#-}

module Process.RNG where

import Control.Monad

import Control.Distributed.Process
import Control.Distributed.Process.Backend.SimpleLocalnet
import Control.Concurrent
import           Data.Map (Map)
import qualified Data.Map as M
import Data.Time.Clock.System
import Data.List
import Data.Maybe

import Data.Binary
import GHC.Generics

import System.Random.MWC

import Msg
import Scratchpad(show2Float)

-- | Process functionality related to generating new messages
initRNG :: GenIO -> Process ()
initRNG gen_io = do
    say "RNG: Spawned"
    register "rng" =<< getSelfPid 
    loopRNG gen_io
    
loopRNG :: GenIO -> Process ()
loopRNG gen_io = do
    liftIO $ threadDelay 500000
    d <- liftIO $ uniform gen_io
    t <- liftIO $ getSystemTime 
    n <- getSelfNode
    say $ concat ["RNG: Generated new value ", show d]
    nsend "citizen" (PropagateMsg n d t) 
    loopRNG gen_io


-- [Requesting data]
-- ~~~~~~~~~~~~~~~~~
--
-- A process might get killed, exited, disconnected, etc.
-- One way to increase reliability is to store the chain locally.
-- Other, complementary way is to request data from other nodes.
--
-- Killing, turning off the node -> Storing the chain locally, request data from other nodes.
-- (use hashes?)
-- Temporary disconnections
-- 






