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
    -- Generate first msg
    msg <- liftIO$ firstMsg gen_io
    n   <- getSelfNode 
    -- Send first msg
    say $ concat ["RNG: Generated first value ", show2Float (msgVal msg)]
    nsend "citizen" (PropagateMsg n msg) 
    -- Loop
    loopRNG msg gen_io
    
loopRNG :: Msg        -- ^ Last message
        -> GenIO 
        -> Process ()
loopRNG msg gen_io = do
    liftIO $ threadDelay 500000
    -- Generate msg
    new_msg <- liftIO$ generateMsg gen_io msg
    n   <- getSelfNode
    -- Send msg
    say $ concat ["RNG: Generated new value ", show2Float (msgVal new_msg)]
    nsend "citizen" (PropagateMsg n new_msg) 
    -- loop
    loopRNG new_msg gen_io


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






