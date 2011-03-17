{- |
Module      :  $Header$
Description :  xml input for Hets development graphs
Copyright   :  (c) Simon Ulbricht, DFKI GmbH 2011
License     :  GPLv2 or higher, see LICENSE.txt
Maintainer  :  tekknix@tzi.de
Stability   :  provisional
Portability :  non-portable (DevGraph)

create new or extend a Development Graph in accordance with an XML input
-}

module Static.FromXml where

import Static.DevGraph
import Static.GTheory

import Common.Result (Result (..))

import Logic.ExtSign (ext_empty_signature)
import Logic.Logic (AnyLogic (..))
import Logic.Prover (noSens)
import Logic.Grothendieck 

import qualified Data.Map as Map (lookup)
import Data.List (partition, isInfixOf)
import Data.Graph.Inductive.Graph (LNode)
import Data.Maybe (fromJust)

import Text.XML.Light


-- | for faster access, some elements attributes are stored alongside
-- as a String
type NamedNode = (String,Element)

data NamedLink = Link { src :: String
                      , trg :: String
                      , srcNode :: Maybe (LNode DGNodeLab)
                      , element :: Element }

-- | main function; receives an logicGraph and an initial DGraph, then adds
-- all nodes and edges from an xml element into the DGraph 
fromXml :: LogicGraph -> DGraph -> Element -> DGraph
fromXml lg dg el = case Map.lookup (currentLogic lg) (logics lg) of
  Nothing ->
    error "FromXml.FromXml: current logic was not found in logicMap"
  Just (Logic lid) -> let
    emptyTheory = G_theory lid (ext_empty_signature lid)
                    startSigId noSens startThId
    nodes = extractNodeElements el
    links = extractLinkElements el
    (dg', depNodes) = initialiseNodes dg emptyTheory nodes links
    in iterateLinks lg dg' depNodes links


-- | All nodes are taken from the xml-element. Then, the name-attribute is
-- looked up and stored alongside the node for easy access. Nodes with no names
-- are ignored (and should never occur).
extractNodeElements :: Element -> [NamedNode]
extractNodeElements = foldr f [] . findChildren (unqual "DGNode") where
  f e r = case findAttr (unqual "name") e of
            Just name -> (name, e) : r
            Nothing -> r


-- | All links are taken from the xml-element. The links have then to be 
-- filtered so that only definition links are considered. Then, the source and
-- target attributes are looked up and stored alongside the link access. Links
-- with source or target information missing are irgnored.
extractLinkElements :: Element -> [NamedLink]
extractLinkElements = foldr f [] . filter isDef . 
                    findChildren (unqual "DGLink") where
  f e r = case findAttr (unqual "source") e of
            Just sr -> case findAttr (unqual "target") e of
              Just tr -> (Link sr tr Nothing e) : r
              Nothing -> r
            Nothing -> r
  isDef e = case findChild (unqual "Type") e of
              Just tp -> isInfixOf "Def" $ strContent tp
              Nothing -> False


-- |  All nodes that do not have dependencies via the links are processed at 
-- the beginning and written into the DGraph. The remaining nodes are returned
-- as well for further processing.
initialiseNodes :: DGraph -> G_theory -> [NamedNode] -> [NamedLink] 
                -> (DGraph,[NamedNode])
initialiseNodes dg gt nodes links = let 
  targets = map trg links
  -- all nodes that are not targeted by any links are considered independent
  (dep, indep) = partition ((`elem` targets) . fst) nodes
  dg' = foldr (insertNodeDG gt) dg indep
  in (dg',dep)


-- | This is the main loop. In every step, all links are extracted which source
-- has already been processed. Then, for each of these links, the target node
-- is calculated and stored using the sources G_theory (If a node is targeted
-- by more than one link, refer to insMultTrg).
-- The function is called again with the remaining links and additional nodes
-- (stored in DGraph) until the list of links reaches null.
iterateLinks :: LogicGraph -> DGraph -> [NamedNode] -> [NamedLink] -> DGraph
iterateLinks _ dg _ [] = dg
iterateLinks lg dg nodes links = let (cur,lftL) = splitLinks dg links
                                     (dg',lftN) = processNodes lg nodes cur dg
  in if null cur then error $
      "FromXml.iterateLinks: remaining links cannot be processed!\n" 
        ++ printLinks lftL
    else iterateLinks lg dg' lftN lftL


-- | Help function for iterateLinks. 
-- For every Node, all Links targeting this Node are collected. Then the Node
-- is processed depending on if none, one or multiple Links are targeting it.
-- Returns updated DGraph and the list of nodes that have not been captured.
processNodes :: LogicGraph -> [NamedNode] -> [NamedLink] -> DGraph
             -> (DGraph,[NamedNode])
processNodes _ nodes [] dg = (dg,nodes)
processNodes _ [] links _ = error $ 
    "FromXml.processNodes: remaining links targets cannot be found!\n"
      ++ printLinks links
processNodes lg (x@(name,_):xs) links dg = 
  case partition ((== name) . trg) links of
    ([l],ls) -> processNodes lg xs ls $ insertEdgeDG lg l
       $ insertNodeDG (thOfSrc l) x dg
    ([],_) -> let (dg',xs') = processNodes lg xs links dg
      in (dg',x:xs')
    (sameTrg,ls) -> processNodes lg xs ls $ insMultTrg lg x sameTrg dg


-- | if multiple links target one node, a G_theory must be calculated using
-- the signature of all ingoing links via gSigUnion.
insMultTrg :: LogicGraph -> NamedNode -> [NamedLink] -> DGraph -> DGraph
insMultTrg lg x links dg = let
  signs = map (signOf . thOfSrc) links
  res = gsigManyUnion lg signs
  in case maybeResult res of
    Nothing -> error $ "FromXml.insMultTrg:\n" ++ show res
    Just (G_sign lid sign sId) -> let gt = noSensGTheory lid sign sId
      in foldr (insertEdgeDG lg) (insertNodeDG gt x dg) links


-- | returns the G_theory of a links source node
thOfSrc :: NamedLink -> G_theory
thOfSrc = dgn_theory . snd . fromJust . srcNode


-- | returns a String representation of a list of links showing their
-- source and target nodes.
printLinks :: [NamedLink] -> String
printLinks = let show' l = src l ++ " -> " ++ trg l in
  unlines . (map show')


-- | Help function for iterateNodes. Given a list of links, it partitions the
-- links depending on if their source has been processed.
splitLinks :: DGraph -> [NamedLink] -> ([NamedLink],[NamedLink])
splitLinks dg = killMultTrg . foldr partition' ([],[]) where
  partition' l (r,r') = case getNodeByName (src l) dg of
    Nothing -> (r, l:r')
    dgn -> (l { srcNode = dgn }:r, r')
  -- if a link targets a node that is also targeted by another link which
  -- cannot be processed at this step, the first link is also appended.
  killMultTrg (hasSrc,noSrc) = let noSrcTrgs = map trg noSrc in
    foldr (\l (r,r') -> if elem (trg l) noSrcTrgs
      then (r, l:r') else (l:r, r')) ([],noSrc) hasSrc


-- | A Node is looked up via its name in the DGraph. Returns the node only
-- if one single node is found for the respective name, otherwise an error
-- is thrown.
getNodeByName :: String -> DGraph -> Maybe (LNode DGNodeLab)
getNodeByName s dg = case lookupNodeByName s dg of
  [n] -> Just n
  [] -> Nothing
  _ -> error $ "FromXml.getNodeByName: ambiguous occurence for " ++ s ++ "!"


-- | Inserts a new edge into the DGraph.
-- This function is the reason why the logicGraph is passed through, because
-- it implements Grothendieck.ginclusion for getting the links GMorphism.
insertEdgeDG :: LogicGraph -> NamedLink -> DGraph -> DGraph
insertEdgeDG lg l dg = let
  (i,lbl1) = fromJust $ srcNode l
  (j,lbl2) = fromJust $ getNodeByName (trg l) dg
  gsign = signOf . dgn_theory
  resMorph = ginclusion lg (gsign lbl1) (gsign lbl2)
  morph = case maybeResult resMorph of
    Just m -> m
    Nothing -> error $ "FromXml.insertEdgeDG':\n" ++ show resMorph
  in snd $ insLEdgeDG (i, j, globDefLink morph SeeTarget) dg 

 
-- | Writes a single Node into the DGraph
insertNodeDG :: G_theory -> NamedNode -> DGraph -> DGraph
insertNodeDG gt ele dg = let lbl = mkDGNodeLab gt ele
                             n = getNewNodeDG dg
  in insLNodeDG (n,lbl) dg


-- | Generates a new DGNodeLab with a startoff-G_theory and an Element
mkDGNodeLab :: G_theory -> NamedNode -> DGNodeLab
mkDGNodeLab gt (name, el) = case extractSpecString el of
  "" -> newNodeLab (parseNodeName name) DGBasic gt
  specs -> let 
    (response,message) = extendByBasicSpec specs gt
    in case response of
      Failure _ -> error $ "FromXml.mkDGNodeLab: "++message
      Success gt' _ symbs _ -> 
        newNodeLab (parseNodeName name) (DGBasicSpec Nothing symbs) gt'


-- | Extracts a String including all Axioms, Theorems and Symbols from the
-- xml-Element (supposedly for one Node only).
extractSpecString :: Element -> String
extractSpecString e = let
  specs = map unqual ["Axiom","Theorem","Symbol"]
  elems = deepSearch specs e
  in unlines $ map strContent elems


-- | custom xml-search for not only immediate children
deepSearch :: [QName] -> Element -> [Element]
deepSearch names e = filterChildrenName (`elem` names) e ++
  concat (map (deepSearch names) (elChildren e))

