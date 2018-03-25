{-#LANGUAGE DeriveGeneric  #-}
{-#LANGUAGE DeriveAnyClass #-}
{-#LANGUAGE RecordWildCards #-}

module Main where

import GHC.Generics
import Data.Binary

import           Control.Distributed.Process
import qualified Control.Distributed.Process.Node as N
import           Control.Distributed.Process.Backend.SimpleLocalnet

import Control.Concurrent
import Control.Concurrent.Async
import Data.ByteString.Char8 (pack)
import Data.List
import Data.Semigroup ((<>))
import qualified Data.Vector.Unboxed as U

import Options.Applicative
import System.Environment (getArgs)
import System.Random.MWC
import System.IO 

import Unsafe.Coerce

import Process
import Config

data CmdOptions = CmdOptions 
    { msg_time   :: Double
    , grace_time :: Double
    , seed       :: String
    , spawn_speed:: Word
    , conf_file  :: String
    } deriving (Show, Eq)

parseCmdOptions = CmdOptions
               <$> option auto
                   ( long "send-for"
                  <> metavar "k" 
                  <> help "Send messages for k seconds"
                  <> value 5)
               <*> option auto
                   ( long "wait-for"
                  <> metavar "l" 
                  <> help "Grace period duration, in seconds"
                  <> value 2)
               <*> strOption 
                   ( long "with-seed"
                  <> help "RNG seed, up to 256 elements will be used" 
                  <> value "")
               <*> option auto
                   ( long "rng-interval"
                  <> help "Time between generating new msgs, in microseconds."
                  <> value 750000)
               <*> strOption 
                   ( long "conf"
                  <> help "Cluster configuration for local nodes" 
                  <> value "config/nodes.txt")


-- | Convert a string into vector of word 32.
-- TODO: Do a safe version.
strToSeed :: String -> U.Vector Word32
strToSeed str = U.fromList $ map unsafeCoerce str

-- | Create a new node and spawn a superivor process for a given role
newNode :: U.Vector Word32 -- ^ seed
        -> Double
        -> Double
        -> Word            -- ^ Interval
        -> Config
        -> IO ()
newNode seed mt gt inter (Config host port role) = do
    backend   <- initializeBackend host port N.initRemoteTable
    localNode <- newLocalNode backend
    gen_io <- initialize seed
    case role of 
        Generator -> N.runProcess localNode (initSupervisor mt gt inter (Just gen_io) backend)   
        Normal    -> N.runProcess localNode (initSupervisor mt gt inter (Nothing    ) backend)   

opts = info (parseCmdOptions <**> helper) 
      ( fullDesc
     <> progDesc "Simple program generating messages over a local network"
     <> header "IOHK task"
      )

main :: IO ()
main = do
    (CmdOptions mt gt seed inter nds_cfg) <- execParser opts
    nodes <- readConfigFile nds_cfg
    -- Set stderr and stdout buffering...
    hSetBuffering stderr LineBuffering
    hSetBuffering stdout LineBuffering 
    -- Spawn nodes asynchronously.
    asyncs <- mapM (asyncBound.newNode (strToSeed seed) mt gt inter) nodes
    mapM_ wait asyncs
    threadDelay 3000000
