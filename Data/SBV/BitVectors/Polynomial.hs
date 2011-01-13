-----------------------------------------------------------------------------
-- |
-- Module      :  Data.SBV.BitVectors.Polynomials
-- Copyright   :  (c) Levent Erkok
-- License     :  BSD3
-- Maintainer  :  erkokl@gmail.com
-- Stability   :  experimental
-- Portability :  portable
--
-- Implementation of polynomial arithmetic
-----------------------------------------------------------------------------

{-# LANGUAGE TypeSynonymInstances #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE PatternGuards #-}

module Data.SBV.BitVectors.Polynomial (Polynomial(..)) where

import Data.Bits
import Data.List(genericTake)
import Data.Maybe(fromJust)
import Data.Word

import Data.SBV.BitVectors.Data
import Data.SBV.BitVectors.Model
import Data.SBV.BitVectors.Splittable
import Data.SBV.Utils.Boolean

-- | Implements polynomial addition, multiplication, division, and modulus operations
-- over GF(2^n).  NB. Similar to 'bvQuotRem', division by @0@ is interpreted as follows:
--
--     @x `pDivMod` 0 = (0, x)@
--
-- for all @x@ (including @0@)
--
-- Minimal complete definiton: 'pMult', 'pDivMod', 'showPoly'
class Bits a => Polynomial a where
 -- | Given bit-positions to be set, create a polynomial
 -- For instance
 --
 --     @polynomial [0, 1, 3] :: SWord8@
 -- 
 -- will evaluate to @11@, since it sets the bits @0@, @1@, and @3@. Mathematicans would write this polynomial
 -- as @x^3 + x + 1@. And in fact, 'showPoly' will show it like that.
 polynomial :: [Int] -> a
 -- | Add two polynomials in GF(2^n)
 pAdd  :: a -> a -> a
 -- | Multiply two polynomials in GF(2^n)
 pMult :: a -> a -> a
 -- | Divide two polynomials in GF(2^n), see above note for division by 0
 pDiv  :: a -> a -> a
 -- | Compute modulus of two polynomials in GF(2^n), see above note for modulus by 0
 pMod  :: a -> a -> a
 -- | Division and modulus packed together
 pDivMod :: a -> a -> (a, a)
 -- | Display a polynomial like a mathematician would (over the monomial @x@)
 showPoly :: a -> String

 -- defaults.. Minumum complete definition: pMult, pDivMod, showPoly
 polynomial = foldr (flip setBit) 0
 pAdd       = xor
 pDiv x y   = fst (pDivMod x y)
 pMod x y   = snd (pDivMod x y)

instance Polynomial Word8   where {showPoly = sp;       pMult = lift polyMult; pDivMod = liftC polyDivMod}
instance Polynomial Word16  where {showPoly = sp;       pMult = lift polyMult; pDivMod = liftC polyDivMod}
instance Polynomial Word32  where {showPoly = sp;       pMult = lift polyMult; pDivMod = liftC polyDivMod}
instance Polynomial Word64  where {showPoly = sp;       pMult = lift polyMult; pDivMod = liftC polyDivMod}
instance Polynomial SWord8  where {showPoly = liftS sp; pMult = polyMult;      pDivMod = polyDivMod}
instance Polynomial SWord16 where {showPoly = liftS sp; pMult = polyMult;      pDivMod = polyDivMod}
instance Polynomial SWord32 where {showPoly = liftS sp; pMult = polyMult;      pDivMod = polyDivMod}
instance Polynomial SWord64 where {showPoly = liftS sp; pMult = polyMult;      pDivMod = polyDivMod}

lift :: SymWord a => (SBV a -> SBV a -> SBV a) -> a -> a -> a
lift f x y = fromJust $ unliteral (f (literal x) (literal y))
liftC :: SymWord a => (SBV a -> SBV a -> (SBV a, SBV a)) -> a -> a -> (a, a)
liftC f x y = let (a, b) = f (literal x) (literal y) in (fromJust (unliteral a), fromJust (unliteral b))
liftS :: SymWord a => (a -> String) -> SBV a -> String
liftS f s
  | Just x <- unliteral s = f x
  | True                  = show s

-- | Pretty print as a polynomial
sp :: Bits a => a -> String
sp a
 | null cs = "0" ++ t
 | True    = foldr (\x y -> sh x ++ " + " ++ y) (sh (last cs)) (init cs) ++ t
 where t  = " :: GF(2^" ++ show n ++ ")"
       n  = bitSize a
       is = [n-1, n-2 .. 0]
       cs = map fst $ filter snd $ zip is (map (testBit a) is)
       sh 0 = "1"
       sh 1 = "x"
       sh i = "x^" ++ show i

-- | Add two polynomials
addPoly :: [SBool] -> [SBool] -> [SBool]
addPoly xs    []      = xs
addPoly []    ys      = ys
addPoly (x:xs) (y:ys) = x <+> y : addPoly xs ys

ites :: SBool -> [SBool] -> [SBool] -> [SBool]
ites s xs ys
 | Just t <- unliteral s
 = if t then xs else ys
 | True
 = go xs ys
 where go [] []         = []
       go []     (b:bs) = ite s false b : go [] bs
       go (a:as) []     = ite s a false : go as []
       go (a:as) (b:bs) = ite s a b : go as bs

-- | Multiply two polynomials, note that the result might overflow! We'll ignore higher-order bits
polyMult :: (Bits a, SymWord a, FromBits (SBV a)) => SBV a -> SBV a -> SBV a
polyMult x y = fromBitsLE $ genericTake sz $ mul xs ys [] ++ repeat false
  where xs = blastLE x
        ys = blastLE y
        sz = sizeOf x
        mul _  []     ps = ps
        mul as (b:bs) ps = mul (false:as) bs (ites b (as `addPoly` ps) ps)

polyDivMod :: (Bits a, SymWord a, FromBits (SBV a)) => SBV a -> SBV a -> (SBV a, SBV a)
polyDivMod x y = ite (y .== 0) (0, x) (adjust d, adjust r)
   where adjust xs = fromBitsLE $ genericTake sz $ xs ++ repeat false
         sz     = sizeOf x
         (d, r) = mdp (blastLE x) (blastLE y)

-- conservative over-approximation of the degree
degree :: [SBool] -> Int
degree xs = walk (length xs - 1) $ reverse xs
  where walk n []     = n
        walk n (b:bs)
         | Just t <- unliteral b
         = if t then n else walk (n-1) bs
         | True
         = n -- over-estimate

mdp :: [SBool] -> [SBool] -> ([SBool], [SBool])
mdp xs ys = go (length ys - 1) (reverse ys)
  where degTop  = degree xs
        go _ []     = error "SBV.Polynomial.mdp: Impossible happened; exhausted ys before hitting 0"
        go n (b:bs)
         | n == 0   = (reverse qs, rs)
         | True     = let (rqs, rrs) = go (n-1) bs
                      in (ites b (reverse qs) rqs, ites b rs rrs)
         where degQuot = degTop - n
               ys' = replicate degQuot false ++ ys
               (qs, rs) = divx (degQuot+1) degTop xs ys'

-- return the element at index i; if not enough elements, return false
-- N.B. equivalent to '(xs ++ repeat false) !! i', but more efficient
idx :: [SBool] -> Int -> SBool
idx []     _ = false
idx (x:_)  0 = x
idx (_:xs) i = idx xs (i-1)

divx :: Int -> Int -> [SBool] -> [SBool] -> ([SBool], [SBool])
divx n _ xs _ | n <= 0 = ([], xs)
divx n i xs ys'        = (q:qs, rs)
  where q        = xs `idx` i
        xs'      = ites q (xs `addPoly` ys') xs
        (qs, rs) = divx (n-1) (i-1) xs' (tail ys')
