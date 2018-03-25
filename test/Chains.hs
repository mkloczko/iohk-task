{-#LANGUAGE ScopedTypeVariables #-}
{-#LANGUAGE FlexibleInstances#-}
module Main where

--Tested modules
import Process.Citizen
import Msg

import Data.Time.Clock.System
import Data.ByteString.Char8 (pack)
import qualified Data.Sequence as SQ
import qualified Data.Set      as S

import Data.Foldable
import Data.List

import Test.Hspec
import Test.QuickCheck

-- Generate a chain
-- Remove some messages
-- Add the removed messages to the chain
-- Have the whole chain again!


instance {-#OVERLAPPING #-} Arbitrary [Msg] where
    arbitrary = do
        (v:vals)<- listOf1 (choose (0,1) :: Gen Double)
        init_bs <- return firstHashSeed --pack <$> (arbitrary  :: Gen String)
        let first_msg = Msg v (MkSystemTime 0 0) (hasher init_bs v)
        return $ reverse $ scanl' (\(Msg v t h) nv -> Msg nv t (hasher h nv)) first_msg vals 
        

tests :: Spec
tests = do
  describe "Chain" $ do
    it "Removing elements from a proper chain and inserting them back will return a proper chain" $ do
       property (\(msgs :: [Msg]) ->  do
          taken_out <- generate $ sublistOf msgs
          let left        = msgs \\ taken_out
              chain_ok    = Chain (SQ.fromList msgs) (S.fromList $ map msgHash msgs) 
              state_ok    = State chain_ok SQ.empty
              -- Tested states
              state_empty = State (Chain SQ.empty S.empty) SQ.empty
              state_bad   = foldl' (\st m -> maybe st id (addMsgState m st)) state_empty left
              state_test  = foldl' (\st m -> maybe st id (addMsgState m st)) state_bad  taken_out
          
          putStrLn $ show left
          putStrLn $ show state_bad
          putStrLn $ show taken_out
          putStrLn $ show state_test
          putStrLn ""


          state_test `shouldBe` state_ok)



main = hspec tests
