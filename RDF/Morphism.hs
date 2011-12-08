{- |
Module      :  $Header$
Description :  RDF Morphism
Copyright   :  (c) Francisc-Nicolae Bungiu, Felix Gabriel Mance, 2011
License     :  GPLv2 or higher, see LICENSE.txt

Maintainer  :  f.bungiu@jacobs-university.de
Stability   :  provisional
Portability :  portable

Morphisms for RDF
-}

module RDF.Morphism where

import OWL2.AS
import RDF.AS
import RDF.Sign
import RDF.Function
import RDF.StaticAnalysis
import RDF.Print
import RDF.Symbols
import Common.DocUtils
import Common.Doc
import Common.Lib.State
import Common.Lib.MapSet (setToMap)
import Common.Result
import Control.Monad

import Data.Maybe

import qualified Data.Set as Set
import qualified Data.Map as Map

data RDFMorphism = RDFMorphism
  { osource :: Sign
  , otarget :: Sign
  , mmaps :: MorphMap
  , pmap :: StringMap
  } deriving (Show, Eq, Ord)

inclRDFMorphism :: Sign -> Sign -> RDFMorphism
inclRDFMorphism s t = RDFMorphism
 { osource = s
 , otarget = t
 , pmap = Map.empty
 , mmaps = Map.empty }

isRDFInclusion :: RDFMorphism -> Bool
isRDFInclusion m = Map.null (pmap m)
  && Map.null (mmaps m) && isSubSign (osource m) (otarget m)
  
symMap :: MorphMap -> Map.Map RDFEntity RDFEntity
symMap = Map.mapWithKey (\ (RDFEntity ty _) -> RDFEntity ty)

inducedElems :: MorphMap -> [RDFEntity]
inducedElems = Map.elems . symMap

inducedSign :: MorphMap -> StringMap -> Sign -> Sign
inducedSign m t s =
    let new = execState (do
            mapM_ (modEntity Set.delete) $ Map.keys m
            mapM_ (modEntity Set.insert) $ inducedElems m) s
    in function Rename (StringMap t) new

inducedPref :: String -> String -> Sign -> (MorphMap, StringMap)
    -> (MorphMap, StringMap)
inducedPref v u sig (m, t) =
    let pm = Map.empty
    in if Set.member v $ Map.keysSet pm
         then if u == v then (m, t) else (m, Map.insert v u t)
        else error $ "unknown symbol: " ++ showDoc v "\n" ++ shows sig ""
        
inducedFromMor :: Map.Map RawSymb RawSymb -> Sign -> Result RDFMorphism
inducedFromMor rm sig = do
  let syms = symOf sig
  (mm, tm) <- foldM (\ (m, t) p -> case p of
        (ASymbol s@(RDFEntity _ v), ASymbol (RDFEntity _ u)) ->
            if Set.member s syms
            then return $ if u == v then (m, t) else (Map.insert s u m, t)
            else fail $ "unknown symbol: " ++ showDoc s "\n" ++ shows sig ""
        (AnUri v, AnUri u) -> case filter (`Set.member` syms)
          $ map (`RDFEntity` v) rdfEntityTypes of
          [] -> let v2 = showQU v
                    u2 = showQU u
                in return $ inducedPref v2 u2 sig (m, t)
          l -> return $ if u == v then (m, t) else
                            (foldr (`Map.insert` u) m l, t)
        _ -> error "RDF.Morphism.inducedFromMor") (Map.empty, Map.empty)
                        $ Map.toList rm
  return RDFMorphism
    { osource = sig
    , otarget = inducedSign mm tm sig
    , pmap = tm
    , mmaps = mm }

  
symMapOf :: RDFMorphism -> Map.Map RDFEntity RDFEntity
symMapOf mor = Map.union (symMap $ mmaps mor) $ setToMap $ symOf $ osource mor

instance Pretty RDFMorphism where
  pretty m = let
    s = osource m
    srcD = specBraces $ space <> pretty s
    t = otarget m
    in if isRDFInclusion m then
           if isSubSign t s then
              fsep [text "identity morphism over", srcD]
           else fsep
             [ text "inclusion morphism of"
             , srcD
             , text "extended with"
             , pretty $ Set.difference (symOf t) $ symOf s ]
       else fsep
         [ pretty $ mmaps m
         , pretty $ pmap m
         , colon <+> srcD, mapsto <+> specBraces (space <> pretty t) ]
         
legalMor :: RDFMorphism -> Result ()
legalMor m = let mm = mmaps m in unless
  (Set.isSubsetOf (Map.keysSet mm) (symOf $ osource m)
  && Set.isSubsetOf (Set.fromList $ inducedElems mm) (symOf $ otarget m))
        $ fail "illegal RDF morphism"
        
composeMor :: RDFMorphism -> RDFMorphism -> Result RDFMorphism
composeMor m1 m2 =
  let nm = Set.fold (\ s@(RDFEntity ty u) -> let
            t = getIri ty u $ mmaps m1
            r = getIri ty t $ mmaps m2
            in if r == u then id else Map.insert s r) Map.empty
           . symOf $ osource m1
  in return m1
     { otarget = otarget m2
     , pmap = Map.empty
     , mmaps = nm }
     
cogeneratedSign :: Set.Set RDFEntity -> Sign -> Result RDFMorphism
cogeneratedSign s sign =
  let sig2 = execState (mapM_ (modEntity Set.delete) $ Set.toList s) sign
  in if isSubSign sig2 sign then return $ inclRDFMorphism sig2 sign else
         fail "non RDF subsignatures for (co)generatedSign"

generatedSign :: Set.Set RDFEntity -> Sign -> Result RDFMorphism
generatedSign s sign = cogeneratedSign (Set.difference (symOf sign) s) sign

matchesSym :: RDFEntity -> RawSymb -> Bool
matchesSym e@(RDFEntity _ u) r = case r of
  ASymbol s -> s == e
  AnUri s -> s == u || namePrefix u == localPart s && null (namePrefix s)

statSymbItems :: [SymbItems] -> [RawSymb]
statSymbItems = concatMap
  $ \ (SymbItems m us) -> case m of
               Nothing -> map AnUri us
               Just ty -> map (ASymbol . RDFEntity ty) us
               
statSymbMapItems :: [SymbMapItems] -> Result (Map.Map RawSymb RawSymb)
statSymbMapItems =
  foldM (\ m (s, t) -> case Map.lookup s m of
    Nothing -> return $ Map.insert s t m
    Just u -> case (u, t) of
      (AnUri su, ASymbol (RDFEntity _ tu)) | su == tu ->
        return $ Map.insert s t m
      (ASymbol (RDFEntity _ su), AnUri tu) | su == tu -> return m
      _ -> if u == t then return m else
        fail $ "differently mapped symbol: " ++ showDoc s "\nmapped to "
             ++ showDoc u " and " ++ showDoc t "")
  Map.empty
  . concatMap (\ (SymbMapItems m us) ->
      let ps = map (\ (u, v) -> (u, fromMaybe u v)) us in
      case m of
        Nothing -> map (\ (s, t) -> (AnUri s, AnUri t)) ps
        Just ty ->
            let mS = ASymbol . RDFEntity ty
            in map (\ (s, t) -> (mS s, mS t)) ps)

mapSen :: RDFMorphism -> Axiom -> Result Axiom
mapSen m a = do
    let new = function Rename (MorphMap $ mmaps m) a
    return $ function Rename (StringMap $ pmap m) new
  