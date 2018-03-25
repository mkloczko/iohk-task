{-| Module: Scratchpad

Functions that were not sorted into other, more proper modules. 

-}
 

module Scratchpad where

import Foreign.Storable
import Foreign.Ptr

import Data.Word (Word8, Word64)
import Data.Binary
import Data.ByteString.Internal (unsafeCreate, ByteString)
import Data.Bits (shiftR)

import Data.Time.Clock.System
import Unsafe.Coerce
import Numeric


instance Binary SystemTime where
    put (MkSystemTime secs nsecs) = put secs >> put nsecs
    get = MkSystemTime <$> get <*> get
-- Solution from:
-- https://stackoverflow.com/questions/8350814/converting-64-bit-double-to-bytestring-efficiently

{-#INLINE putWord64le#-}
-- | Write a Word64 in little endian format
putWord64le :: Word64 -> Ptr Word8 -> IO()
putWord64le w p = do
  poke p               (fromIntegral (w)           :: Word8)
  poke (p `plusPtr` 1) (fromIntegral (shiftR w  8) :: Word8)
  poke (p `plusPtr` 2) (fromIntegral (shiftR w 16) :: Word8)
  poke (p `plusPtr` 3) (fromIntegral (shiftR w 24) :: Word8)
  poke (p `plusPtr` 4) (fromIntegral (shiftR w 32) :: Word8)
  poke (p `plusPtr` 5) (fromIntegral (shiftR w 40) :: Word8)
  poke (p `plusPtr` 6) (fromIntegral (shiftR w 48) :: Word8)
  poke (p `plusPtr` 7) (fromIntegral (shiftR w 56) :: Word8)


encodeDouble :: Double -> ByteString
encodeDouble x = unsafeCreate 8 (putWord64le $ unsafeCoerce x)


-- | Return the difference in times in doubles.
diffSysTime :: SystemTime -> SystemTime -> Double
diffSysTime (MkSystemTime s1 ns1) (MkSystemTime s2 ns2)
    | ns1 >= ns2 = fromIntegral (s1-s2) + (fromIntegral (ns1 - ns2) / 1000000000) 
    | otherwise  = fromIntegral (s1-s2 -1) + (fromIntegral (1000000000 - (ns2 - ns1)) / 1000000000) 

show2Float f = showFFloat (Just 2) f ""
