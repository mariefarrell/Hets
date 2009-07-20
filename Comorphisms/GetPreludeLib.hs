{- |
Module      :  $Header$
Description :  read a prelude library for some comorphisms
Copyright   :  (c) Christian Maeder and DFKI GmbH 2009
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  Christian.Maeder@dfki.de
Stability   :  experimental
Portability :  portable

read a prelude library for some comorphisms
-}

module Comorphisms.GetPreludeLib where

import Static.AnalysisLibrary
import Driver.Options
import Driver.ReadFn
import Comorphisms.LogicList

import Proofs.ComputeTheory

import Static.DevGraph
import Static.GTheory

import Common.Result
import Common.ResultT

import Data.Maybe
import qualified Data.Map as Map
import qualified Data.Set as Set

readLib :: FilePath -> IO [G_theory]
readLib fp = do
  Result _ mLib <- runResultT $ anaLibFileOrGetEnv preLogicGraph
    defaultHetcatsOpts Set.empty Map.empty
    (fileToLibName defaultHetcatsOpts fp) fp
  case mLib of
    Nothing -> fail $ "library could not be read from: " ++ fp
    Just (ln, le) -> do
      let dg = lookupDGraph ln le
      return . catMaybes . Map.fold (\ ge -> case ge of
        SpecEntry (ExtGenSig _ (NodeSig n _)) ->
           if null $ outDG dg n then
               (maybeResult (computeTheory le ln n) :)
           else id
        _ -> id) [] $ globalEnv dg



