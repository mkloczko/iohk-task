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
import Data.List
import Data.Semigroup ((<>))

import Options.Applicative
import System.Environment (getArgs)
import System.Random.MWC

import Process


data CmdOptions = CmdOptions 
    { msg_time   :: Double
    , grace_time :: Double
    , seed       :: String
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
                  <> help "Starting seed, in hex format" 
                  <> value "")

main :: IO ()
main = do
    [role, host,port] <- getArgs
    backend <- initializeBackend host port N.initRemoteTable 
    localNode <- newLocalNode backend
    gen <- create
    case role of 
       "rng"    -> N.runProcess localNode (initSupervisor 3 2 (Just gen) backend)   
       "normal" -> N.runProcess localNode (initSupervisor 3 2 (Nothing) backend)   
       _      -> return ()
