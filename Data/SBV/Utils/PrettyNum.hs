-----------------------------------------------------------------------------
-- |
-- Module      :  Data.SBV.Utils.PrettyNum
-- Copyright   :  (c) Levent Erkok
-- License     :  BSD3
-- Maintainer  :  erkokl@gmail.com
-- Stability   :  experimental
--
-- Number representations in hex/bin
-----------------------------------------------------------------------------

{-# LANGUAGE FlexibleInstances    #-}
{-# LANGUAGE ScopedTypeVariables  #-}
{-# LANGUAGE TypeSynonymInstances #-}

module Data.SBV.Utils.PrettyNum (
        PrettyNum(..), readBin, shex, shexI, sbin, sbinI
      , showCFloat, showCDouble, showHFloat, showHDouble
      , showSMTFloat, showSMTDouble, smtRoundingMode, cwToSMTLib, mkSkolemZero
      ) where

import Data.Char  (ord, intToDigit, ord)
import Data.Int   (Int8, Int16, Int32, Int64)
import Data.List  (isPrefixOf)
import Data.Maybe (fromJust, fromMaybe, listToMaybe)
import Data.Ratio (numerator, denominator)
import Data.Word  (Word8, Word16, Word32, Word64)
import Numeric    (showIntAtBase, showHex, readInt)

import Data.Numbers.CrackNum (floatToFP, doubleToFP)

import Data.SBV.Core.Data
import Data.SBV.Core.AlgReals (algRealToSMTLib2)

import Data.SBV.SMT.Utils (stringToQFS)

-- | PrettyNum class captures printing of numbers in hex and binary formats; also supporting negative numbers.
--
-- Minimal complete definition: 'hexS' and 'binS'
class PrettyNum a where
  -- | Show a number in hexadecimal (starting with @0x@ and type.)
  hexS :: a -> String
  -- | Show a number in binary (starting with @0b@ and type.)
  binS :: a -> String
  -- | Show a number in hex, without prefix, or types.
  hex :: a -> String
  -- | Show a number in bin, without prefix, or types.
  bin :: a -> String

-- Why not default methods? Because defaults need "Integral a" but Bool is not..
instance PrettyNum Bool where
  {hexS = show; binS = show; hex = show; bin = show}
instance PrettyNum String where
  {hexS = show; binS = show; hex = show; bin = show}
instance PrettyNum Word8 where
  {hexS = shex True True (False,8) ; binS = sbin True True (False,8) ; hex = shex False False (False,8) ; bin = sbin False False (False,8) ;}
instance PrettyNum Int8 where
  {hexS = shex True True (True,8)  ; binS = sbin True True (True,8)  ; hex = shex False False (True,8)  ; bin = sbin False False (True,8)  ;}
instance PrettyNum Word16 where
  {hexS = shex True True (False,16); binS = sbin True True (False,16); hex = shex False False (False,16); bin = sbin False False (False,16);}
instance PrettyNum Int16  where
  {hexS = shex True True (True,16);  binS = sbin True True (True,16) ; hex = shex False False (True,16);  bin = sbin False False (True,16) ;}
instance PrettyNum Word32 where
  {hexS = shex True True (False,32); binS = sbin True True (False,32); hex = shex False False (False,32); bin = sbin False False (False,32);}
instance PrettyNum Int32  where
  {hexS = shex True True (True,32);  binS = sbin True True (True,32) ; hex = shex False False (True,32);  bin = sbin False False (True,32) ;}
instance PrettyNum Word64 where
  {hexS = shex True True (False,64); binS = sbin True True (False,64); hex = shex False False (False,64); bin = sbin False False (False,64);}
instance PrettyNum Int64  where
  {hexS = shex True True (True,64);  binS = sbin True True (True,64) ; hex = shex False False (True,64);  bin = sbin False False (True,64) ;}
instance PrettyNum Integer where
  {hexS = shexI True True; binS = sbinI True True; hex = shexI False False; bin = sbinI False False;}

instance PrettyNum CW where
  hexS cw | isUninterpreted cw = show cw ++ " :: " ++ show (kindOf cw)
          | isBoolean cw       = hexS (cwToBool cw) ++ " :: Bool"
          | isFloat cw         = let CWFloat   f = cwVal cw in show f ++ " :: Float\n"  ++ show (floatToFP f)
          | isDouble cw        = let CWDouble  d = cwVal cw in show d ++ " :: Double\n" ++ show (doubleToFP d)
          | isReal cw          = let CWAlgReal w = cwVal cw in show w ++ " :: Real"
          | isString cw        = let CWString  s = cwVal cw in show s ++ " :: String"
          | not (isBounded cw) = let CWInteger w = cwVal cw in shexI True True w
          | True               = let CWInteger w = cwVal cw in shex  True True (hasSign cw, intSizeOf cw) w

  binS cw | isUninterpreted cw = show cw  ++ " :: " ++ show (kindOf cw)
          | isBoolean cw       = binS (cwToBool cw)  ++ " :: Bool"
          | isFloat cw         = let CWFloat   f = cwVal cw in show f ++ " :: Float\n"  ++ show (floatToFP f)
          | isDouble cw        = let CWDouble  d = cwVal cw in show d ++ " :: Double\n" ++ show (doubleToFP d)
          | isReal cw          = let CWAlgReal w = cwVal cw in show w ++ " :: Real"
          | isString cw        = let CWString  s = cwVal cw in show s ++ " :: String"
          | not (isBounded cw) = let CWInteger w = cwVal cw in sbinI True True w
          | True               = let CWInteger w = cwVal cw in sbin  True True (hasSign cw, intSizeOf cw) w

  hex cw | isUninterpreted cw = show cw
         | isBoolean cw       = hexS (cwToBool cw) ++ " :: Bool"
         | isFloat cw         = let CWFloat   f = cwVal cw in show f
         | isDouble cw        = let CWDouble  d = cwVal cw in show d
         | isReal cw          = let CWAlgReal w = cwVal cw in show w
         | isString cw        = let CWString  s = cwVal cw in show s
         | not (isBounded cw) = let CWInteger w = cwVal cw in shexI False False w
         | True               = let CWInteger w = cwVal cw in shex  False False (hasSign cw, intSizeOf cw) w

  bin cw | isUninterpreted cw = show cw
         | isBoolean cw       = binS (cwToBool cw) ++ " :: Bool"
         | isFloat cw         = let CWFloat  f  = cwVal cw in show f
         | isDouble cw        = let CWDouble d  = cwVal cw in show d
         | isReal cw          = let CWAlgReal w = cwVal cw in show w
         | isString cw        = let CWString  s = cwVal cw in show s
         | not (isBounded cw) = let CWInteger w = cwVal cw in sbinI False False w
         | True               = let CWInteger w = cwVal cw in sbin  False False (hasSign cw, intSizeOf cw) w

instance (SymWord a, PrettyNum a) => PrettyNum (SBV a) where
  hexS s = maybe (show s) (hexS :: a -> String) $ unliteral s
  binS s = maybe (show s) (binS :: a -> String) $ unliteral s
  hex  s = maybe (show s) (hex  :: a -> String) $ unliteral s
  bin  s = maybe (show s) (bin  :: a -> String) $ unliteral s

-- | Show as a hexadecimal value. First bool controls whether type info is printed
-- while the second boolean controls wether 0x prefix is printed. The tuple is
-- the signedness and the bit-length of the input. The length of the string
-- will /not/ depend on the value, but rather the bit-length.
shex :: (Show a, Integral a) => Bool -> Bool -> (Bool, Int) -> a -> String
shex shType shPre (signed, size) a
 | a < 0
 = "-" ++ pre ++ pad l (s16 (abs (fromIntegral a :: Integer)))  ++ t
 | True
 = pre ++ pad l (s16 a) ++ t
 where t | shType = " :: " ++ (if signed then "Int" else "Word") ++ show size
         | True   = ""
       pre | shPre = "0x"
           | True  = ""
       l = (size + 3) `div` 4

-- | Show as a hexadecimal value, integer version. Almost the same as shex above
-- except we don't have a bit-length so the length of the string will depend
-- on the actual value.
shexI :: Bool -> Bool -> Integer -> String
shexI shType shPre a
 | a < 0
 = "-" ++ pre ++ s16 (abs a)  ++ t
 | True
 = pre ++ s16 a ++ t
 where t | shType = " :: Integer"
         | True   = ""
       pre | shPre = "0x"
           | True  = ""

-- | Similar to 'shex'; except in binary.
sbin :: (Show a, Integral a) => Bool -> Bool -> (Bool, Int) -> a -> String
sbin shType shPre (signed,size) a
 | a < 0
 = "-" ++ pre ++ pad size (s2 (abs (fromIntegral a :: Integer)))  ++ t
 | True
 = pre ++ pad size (s2 a) ++ t
 where t | shType = " :: " ++ (if signed then "Int" else "Word") ++ show size
         | True   = ""
       pre | shPre = "0b"
           | True  = ""

-- | Similar to 'shexI'; except in binary.
sbinI :: Bool -> Bool -> Integer -> String
sbinI shType shPre a
 | a < 0
 = "-" ++ pre ++ s2 (abs a) ++ t
 | True
 =  pre ++ s2 a ++ t
 where t | shType = " :: Integer"
         | True   = ""
       pre | shPre = "0b"
           | True  = ""

-- | Pad a string to a given length. If the string is longer, then we don't drop anything.
pad :: Int -> String -> String
pad l s = replicate (l - length s) '0' ++ s

-- | Binary printer
s2 :: (Show a, Integral a) => a -> String
s2  v = showIntAtBase 2 dig v "" where dig = fromJust . flip lookup [(0, '0'), (1, '1')]

-- | Hex printer
s16 :: (Show a, Integral a) => a -> String
s16 v = showHex v ""

-- | A more convenient interface for reading binary numbers, also supports negative numbers
readBin :: Num a => String -> a
readBin ('-':s) = -(readBin s)
readBin s = case readInt 2 isDigit cvt s' of
              [(a, "")] -> a
              _         -> error $ "SBV.readBin: Cannot read a binary number from: " ++ show s
  where cvt c = ord c - ord '0'
        isDigit = (`elem` "01")
        s' | "0b" `isPrefixOf` s = drop 2 s
           | True                = s

-- | A version of show for floats that generates correct C literals for nan/infinite. NB. Requires "math.h" to be included.
showCFloat :: Float -> String
showCFloat f
   | isNaN f             = "((float) NAN)"
   | isInfinite f, f < 0 = "((float) (-INFINITY))"
   | isInfinite f        = "((float) INFINITY)"
   | True                = show f ++ "F"

-- | A version of show for doubles that generates correct C literals for nan/infinite. NB. Requires "math.h" to be included.
showCDouble :: Double -> String
showCDouble f
   | isNaN f             = "((double) NAN)"
   | isInfinite f, f < 0 = "((double) (-INFINITY))"
   | isInfinite f        = "((double) INFINITY)"
   | True                = show f

-- | A version of show for floats that generates correct Haskell literals for nan/infinite
showHFloat :: Float -> String
showHFloat f
   | isNaN f             = "((0/0) :: Float)"
   | isInfinite f, f < 0 = "((-1/0) :: Float)"
   | isInfinite f        = "((1/0) :: Float)"
   | True                = show f

-- | A version of show for doubles that generates correct Haskell literals for nan/infinite
showHDouble :: Double -> String
showHDouble d
   | isNaN d             = "((0/0) :: Double)"
   | isInfinite d, d < 0 = "((-1/0) :: Double)"
   | isInfinite d        = "((1/0) :: Double)"
   | True                = show d

-- | A version of show for floats that generates correct SMTLib literals using the rounding mode
showSMTFloat :: RoundingMode -> Float -> String
showSMTFloat rm f
   | isNaN f             = as "NaN"
   | isInfinite f, f < 0 = as "-oo"
   | isInfinite f        = as "+oo"
   | isNegativeZero f    = as "-zero"
   | f == 0              = as "+zero"
   | True                = "((_ to_fp 8 24) " ++ smtRoundingMode rm ++ " " ++ toSMTLibRational (toRational f) ++ ")"
   where as s = "(_ " ++ s ++ " 8 24)"

-- | A version of show for doubles that generates correct SMTLib literals using the rounding mode
showSMTDouble :: RoundingMode -> Double -> String
showSMTDouble rm d
   | isNaN d             = as "NaN"
   | isInfinite d, d < 0 = as "-oo"
   | isInfinite d        = as "+oo"
   | isNegativeZero d    = as "-zero"
   | d == 0              = as "+zero"
   | True                = "((_ to_fp 11 53) " ++ smtRoundingMode rm ++ " " ++ toSMTLibRational (toRational d) ++ ")"
   where as s = "(_ " ++ s ++ " 11 53)"

-- | Show a rational in SMTLib format
toSMTLibRational :: Rational -> String
toSMTLibRational r
   | n < 0
   = "(- (/ "  ++ show (abs n) ++ ".0 " ++ show d ++ ".0))"
   | True
   = "(/ " ++ show n ++ ".0 " ++ show d ++ ".0)"
  where n = numerator r
        d = denominator r

-- | Convert a rounding mode to the format SMT-Lib2 understands.
smtRoundingMode :: RoundingMode -> String
smtRoundingMode RoundNearestTiesToEven = "roundNearestTiesToEven"
smtRoundingMode RoundNearestTiesToAway = "roundNearestTiesToAway"
smtRoundingMode RoundTowardPositive    = "roundTowardPositive"
smtRoundingMode RoundTowardNegative    = "roundTowardNegative"
smtRoundingMode RoundTowardZero        = "roundTowardZero"

-- | Convert a CW to an SMTLib2 compliant value
cwToSMTLib :: RoundingMode -> CW -> String
cwToSMTLib rm x
  | isBoolean       x, CWInteger  w      <- cwVal x = if w == 0 then "false" else "true"
  | isUninterpreted x, CWUserSort (_, s) <- cwVal x = roundModeConvert s
  | isReal          x, CWAlgReal  r      <- cwVal x = algRealToSMTLib2 r
  | isFloat         x, CWFloat    f      <- cwVal x = showSMTFloat  rm f
  | isDouble        x, CWDouble   d      <- cwVal x = showSMTDouble rm d
  | not (isBounded x), CWInteger  w      <- cwVal x = if w >= 0 then show w else "(- " ++ show (abs w) ++ ")"
  | not (hasSign x)  , CWInteger  w      <- cwVal x = smtLibHex (intSizeOf x) w
  -- signed numbers (with 2's complement representation) is problematic
  -- since there's no way to put a bvneg over a positive number to get minBound..
  -- Hence, we punt and use binary notation in that particular case
  | hasSign x        , CWInteger  w      <- cwVal x = if w == negate (2 ^ intSizeOf x)
                                                      then mkMinBound (intSizeOf x)
                                                      else negIf (w < 0) $ smtLibHex (intSizeOf x) (abs w)
  | isString x       , CWString s        <- cwVal x = stringToQFS s
  | True = error $ "SBV.cvtCW: Impossible happened: Kind/Value disagreement on: " ++ show (kindOf x, x)
  where roundModeConvert s = fromMaybe s (listToMaybe [smtRoundingMode m | m <- [minBound .. maxBound] :: [RoundingMode], show m == s])
        -- Carefully code hex numbers, SMTLib is picky about lengths of hex constants. For the time
        -- being, SBV only supports sizes that are multiples of 4, but the below code is more robust
        -- in case of future extensions to support arbitrary sizes.
        smtLibHex :: Int -> Integer -> String
        smtLibHex 1  v = "#b" ++ show v
        smtLibHex sz v
          | sz `mod` 4 == 0 = "#x" ++ pad (sz `div` 4) (showHex v "")
          | True            = "#b" ++ pad sz (showBin v "")
           where showBin = showIntAtBase 2 intToDigit
        negIf :: Bool -> String -> String
        negIf True  a = "(bvneg " ++ a ++ ")"
        negIf False a = a

        -- anamoly at the 2's complement min value! Have to use binary notation here
        -- as there is no positive value we can provide to make the bvneg work.. (see above)
        mkMinBound :: Int -> String
        mkMinBound i = "#b1" ++ replicate (i-1) '0'

-- | Create a skolem 0 for the kind
mkSkolemZero :: RoundingMode -> Kind -> String
mkSkolemZero _ (KUserSort _ (Right (f:_))) = f
mkSkolemZero _ (KUserSort s _)             = error $ "SBV.mkSkolemZero: Unexpected uninterpreted sort: " ++ s
mkSkolemZero rm k                          = cwToSMTLib rm (mkConstCW k (0::Integer))
