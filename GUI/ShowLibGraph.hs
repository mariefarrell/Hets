{-# OPTIONS -cpp #-}
{- |
Module      :  $Header$
Copyright   :  (c) Uni Bremen 2003-2007
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  raider@tzi.de
Stability   :  unstable
Portability :  non-portable

This Modul provides a function to display a Library Dependency Graph. Just the ShowLibGraph function is exported.

-}

module GUI.ShowLibGraph
  (showLibGraph)
where

import Driver.Options(HetcatsOpts)
import Syntax.AS_Library
import ATC.AS_Library()
import Static.DevGraph
--import GUI.ShowGraph

-- for graph display
import DaVinciGraph
import GraphDisp
import GraphConfigure

-- for windows display
import TextDisplay
import Configuration

import qualified Data.Map as Map
import qualified Data.IntMap as IntMap
import qualified Common.Lib.Rel as Rel
import qualified Common.Lib.Graph as Tree

import Data.List

{- | Creates a  new uDrawGraph Window and shows the Library Dependency Graph of
     the given LibEnv.-}
showLibGraph :: HetcatsOpts -> LibEnv -> IO ()
showLibGraph opts le =
  do
    let
      lookup' x y = Map.findWithDefault
                    (error "lookup': node not found")
                    y x
      graphParms = GraphTitle "Library Graph" $$
		   OptimiseLayout True $$
		   AllowClose (return True) $$
		   emptyGraphParms
    depG <- newGraph daVinciSort graphParms
    let 
      keys = Map.keys le
      subNodeMenu = LocalMenu( Menu Nothing [
        Button "Show Graph" (runShowGraph opts le), 
        Button "Show spec/View Names" (showSpec le)])
      subNodeTypeParms = subNodeMenu $$$
			 Box $$$
			 ValueTitle (\ x -> return (show x)) $$$
			 Color "green" $$$
			 emptyNodeTypeParms
    subNodeType <- newNodeType depG subNodeTypeParms
    subNodeList <- mapM (newNode depG subNodeType) keys
    let
      nodes = Map.fromList $ zip keys subNodeList
      subArcMenu = LocalMenu( Menu Nothing [])
      subArcTypeParms = subArcMenu $$$
                        ValueTitle id $$$
                        Color "black" $$$
                        emptyArcTypeParms
    subArcType <- newArcType depG subArcTypeParms
    let
      insertSubArc = \ (node1, node2) ->
                          newArc depG subArcType (return "")
                            (lookup' nodes node1)
                            (lookup' nodes node2)
    mapM_ insertSubArc $
      Rel.toList $ Rel.intransKernel $ Rel.transClosure $
      Rel.fromList $ getLibDeps le
    redraw depG
    return ()

-- | Displays the Specs of a Library in a Textwindow
showSpec :: LibEnv -> LIB_NAME -> IO()
showSpec le ln =
  do
    let
      ge = globalEnv $ lookupGlobalContext ln le
      sp = unlines $ map (show) (Map.elems ge)
    createTextDisplay ("Contents of " ++ (show ln)) sp [size(80,25)]

-- | Runs the showGraph function
runShowGraph :: HetcatsOpts -> LibEnv -> LIB_NAME -> IO()
runShowGraph opts le ln = 
  do
    let
      -- | Returns the filepath
      file :: LIB_NAME -> FilePath
      file (Lib_version x _) = show x
      file (Lib_id x) = show x
    --showGraph (file ln) opts (Just (ln, le))
    return ()

-- | Creates a list of all LIB_NAME pairs, which have a dependency
getLibDeps :: LibEnv -> [(LIB_NAME, LIB_NAME)]
getLibDeps le =
  concat $ map (getDep) $ Map.keys le
  where
    -- | Creates a list of LIB_NAME pairs for the fist argument 
    getDep :: LIB_NAME -> [(LIB_NAME, LIB_NAME)]
    getDep ln =
      map (\ x -> (ln, x)) $ map (\ (_,x,_) -> dgn_libname x) $ IntMap.elems $
        IntMap.filter (\ (_,x,_) -> isDGRef x) $ Tree.convertToMap $ 
        devGraph $ lookupGlobalContext ln le
