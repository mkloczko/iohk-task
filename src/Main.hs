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
               <*> strOption 
                   ( long "conf"
                  <> help "Cluster configuration for local nodes" 
                  <> value "nodes.txt")


-- | Convert a string into vector of word 32.
-- TODO: Do a safe version.
strToSeed :: String -> U.Vector Word32
strToSeed str = U.fromList $ map unsafeCoerce str

-- | Create a new node and spawn a superivor process for a given role
newNode :: GenIO  -- ^
        -> Double
        -> Double
        -> Config
        -> IO ()
newNode gen_io mt gt (Config host port role) = do
    backend   <- initializeBackend host port N.initRemoteTable
    localNode <- newLocalNode backend
    case role of 
        Generator -> N.runProcess localNode (initSupervisor mt gt (Just gen_io) backend)   
        Normal    -> N.runProcess localNode (initSupervisor mt gt (Nothing    ) backend)   

opts = info (parseCmdOptions <**> helper) 
      ( fullDesc
     <> progDesc "Simple program generating messages over a local network"
     <> header "IOHK task"
      )

main :: IO ()
main = do
    (CmdOptions mt gt seed nds_cfg) <- execParser opts
    nodes <- readConfigFile nds_cfg
    gen <- initialize (strToSeed seed)
    -- Set stderr and stdout buffering...
    hSetBuffering stderr LineBuffering
    hSetBuffering stdout LineBuffering 
    -- Spawn nodes asynchronously.
    asyncs <- mapM (asyncBound.newNode gen mt gt) nodes
    mapM_ wait asyncs
    threadDelay 3000000
