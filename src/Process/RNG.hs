{-#LANGUAGE RecordWildCards#-}
{-#LANGUAGE TupleSections#-}
{-#LANGUAGE DeriveGeneric #-}
{-#LANGUAGE DeriveAnyClass #-}
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

-- | Save state
saveRNG :: String -> GenIO -> Msg -> IO ()
saveRNG fname gen msg = return () 

-- | Load state, if exists
loadRNG :: String -> IO (Maybe (GenIO, Msg))
loadRNG str = return Nothing

-- | Process functionality related to generating new messages
initRNG :: GenIO -> Word ->  Process ()
initRNG gen_io inter = do
    say "RNG: Spawned"
    register "rng" =<< getSelfPid 
    -- Generate first msg
    msg <- liftIO$ firstMsg gen_io
    n   <- getSelfNode 
    -- Send first msg
    say $ concat ["RNG: Generated first value ", show2Float (msgVal msg)]
    nsend "citizen" (PropagateMsg n msg) 
    -- Loop
    loopRNG msg gen_io (fromIntegral inter)
    
loopRNG :: Msg        -- ^ Last message
        -> GenIO 
        -> Int        -- ^ Interval for msg generation
        -> Process ()
loopRNG msg gen_io inter = do
    liftIO $ threadDelay inter
    -- Generate msg
    new_msg <- liftIO$ generateMsg gen_io msg
    n   <- getSelfNode
    -- Send msg
    say $ concat ["RNG: Generated new value ", show2Float (msgVal new_msg)]
    nsend "citizen" (PropagateMsg n new_msg) 
    -- loop
    loopRNG new_msg gen_io inter


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






