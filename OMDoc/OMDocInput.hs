{- |
Module      :  $Header$
Copyright   :  (c) Hendrik Iben, Uni Bremen 2005-2006
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  hiben@tzi.de
Stability   :  provisional
Portability :  non-portable(Logic)

Input-methods for reading OMDoc
-}
{-
TODO:
  bug:
    When referencing over several imports, sorts are disappearing.
    (e.g. Basic/Graphs.casl can be converted to OMDoc but not back)
-}
module OMDoc.OMDocInput
  (
    mLibEnvFromOMDocFile
  )
{- -- debug 
  (
    -- options currently for debugging, stores HetcatsOptions
     GlobalOptions(..)
    -- reads an OMDoc-File and builds a graph of the files imported
    ,makeImportGraphFullXml
    -- transforms an import graph into a graph holding a DevGraph for
    -- each OMDoc-File (+ document)
    ,processImportGraphXN
    -- strips documents from processed import graph creating a graph of
    -- DevGraphs
    ,hybridGToDGraphG
    -- converts a graph of DevGraphs into a LibEnv (using file names for
    -- library names)
    -- same as above but using the documents id (name) for library name
    ,dGraphGToLibEnvOMDocId
    -- wrapper for Hets that tries to create a LibEnv from an OMDoc file
    -- and returns Nothing on error
    ,mLibEnvFromOMDocFile
    -- executes a sequence of the above functions to create a LibEnv from
    -- an OMDoc file
    ,libEnvFromOMDocFile
    -- loads an xml file via HXT and returns the 'omdoc'-tree
    -- ,loadOMDoc
    ,getImportedTheories
    ,xmlToMorphismMap
    ,fetchRequationSymbols
    ,preprocessXml
  )
-}
  where

import qualified OMDoc.HetsDefs as Hets
import CASL.Sign
import CASL.Morphism
import CASL.Logic_CASL
import CASL.AS_Basic_CASL
import qualified Common.Id as Id
import qualified Syntax.AS_Library as ASL
import qualified CASL.AS_Basic_CASL as ABC

import Static.DevGraph
import qualified Data.Graph.Inductive.Graph as Graph
import qualified Common.Lib.Graph as CLGraph
import CASL.Amalgamability(CASLSign)

-- Often used symbols from HXT
import Text.XML.HXT.Parser
  ( (+++), (.>), xshow, isTag, getChildren, processChildren, getValue
    ,emptyRoot, v_1, v_0, a_issue_errors, a_source, a_validate
    ,a_check_namespaces
  )
        
import qualified Text.XML.HXT.Parser as HXT hiding (run, trace, when)
import qualified Text.XML.HXT.DOM.XmlTreeTypes as HXTT hiding (when)

import qualified Common.Lib.Map as Map
import qualified Common.Lib.Set as Set
import qualified Common.Lib.Rel as Rel

import qualified Common.AS_Annotation as Ann

import qualified Logic.Logic as Logic
import qualified Logic.Prover as Prover

import Data.Maybe (fromMaybe)
import Data.List (isPrefixOf, find)

import qualified Common.GlobalAnnotations as GA

import Debug.Trace (trace)

import qualified System.IO.Error as System.IO.Error

import Driver.Options

import Control.Monad
import Control.Exception as Control.Exception

import Char (isSpace)

import qualified Network.URI as URI

import OMDoc.Util
import OMDoc.Container
import OMDoc.XmlHandling

import OMDoc.OMDocDefs

import qualified System.Directory as System.Directory

{- |
  A wrapper-function for Hets.
  Tries to load an OMDoc file and to create a LibEnv.
  Uses library-path specified in HetcatsOpts to search for imported files.
  On (IO-)error Nothing is returned
-}
mLibEnvFromOMDocFile::
  HetcatsOpts -- ^ setup libdir to search for files
  ->FilePath -- ^ the file to load
  ->IO (Maybe (ASL.LIB_NAME, LibEnv))
mLibEnvFromOMDocFile hco file =
  Control.Exception.catch
    (
      do
        (ln, _, lenv) <- libEnvFromOMDocFile
          (emptyGlobalOptions { hetsOpts = hco })
          file
        return (Just (ln, lenv))
    )
    (\_ -> putIfVerbose hco 0 "Error loading OMDoc!" >> return Nothing)

{- |
  Tries to load an OMDoc file an to create a LibEnv.
  Uses @dGraphGToLibEnvOMDocId@ to create library names.
-}
libEnvFromOMDocFile::
  GlobalOptions -- ^ library path setup with hetsOpts + debugging options
  ->String -- ^ URI \/ File to load
  ->IO (ASL.LIB_NAME, DGraph, LibEnv)
libEnvFromOMDocFile go f =
  makeImportGraphFullXml go f >>=
    return . dGraphGToLibEnvOMDocId go . hybridGToDGraphG go . processImportGraphXN go

{- -- debug
  loads an OMDoc file and returns it even if there are errors
  fatal errors lead to IOError
-}
{-
loadOMDoc ::
  String -- ^ URI \/ File to load
  ->(IO HXT.XmlTrees)
loadOMDoc f =
  do
    tree <- (
      HXT.run' $
      HXT.parseDocument
        [
           (a_source, f)
          ,(a_validate, v_0) -- validation is nice, but HXT does not give back
                             -- even a partial document then...
          ,(a_check_namespaces,v_1) -- needed,really...
          ,(a_issue_errors, v_0)
        ]
        emptyRoot
      )
    status <- return ( (
      read $
      xshow $
      applyXmlFilter (getValue "status") tree
      ) :: Int )
    if status <= HXT.c_err
      then
        return $ applyXmlFilter (getChildren .> isTag "omdoc") tree
      else
        ioError $ userError ("Error loading \"" ++ f ++ "\"")
-}

{- |
  maps a set of (XmlNamedWONIdS, a) tuples to a map using the IdS
  as key and combining a's into sets if they have the same Id
  (ignoring xmlname and origin). A conversion function can be specified to 
  transform a to b where b has to provide an instance of Ord.
-}
mapSameIdToSetWith::
  (Ord b)=>
  (a->b) -- ^ conversion function
  ->Set.Set (XmlNamedWONId, a) -- ^ set to make map of
  ->Map.Map Id.Id (Set.Set b)
mapSameIdToSetWith conv set =
  Set.fold (\(xnwonid, a) mapping ->
    let
      pureid = xnWOaToa xnwonid
      idset = Map.findWithDefault Set.empty pureid mapping
      newset = Set.union idset (Set.singleton $ conv a)
    in
      Map.insert pureid newset mapping
      ) Map.empty set

{- |
  creates a DGNodLab from sorts, relations, predicates, operators and
  sentences
-}
xnMapsToDGNodeLab::
  GlobalOptions -- ^ for debugging
  ->NODE_NAME  -- ^ name for created DGNodeLab
  ->Set.Set XmlNamedWONId -- ^ sorts for this node
  ->Rel.Rel XmlNamedWONId -- ^ sort-relations for this node
  ->Set.Set (XmlNamedWONId, PredTypeXNWON) -- ^ predicates 
  ->Set.Set (XmlNamedWONId, OpTypeXNWON) -- ^ operators
  ->Set.Set (XmlNamed Hets.SentenceWO) -- ^ sentences
  ->DGNodeLab
xnMapsToDGNodeLab
  go
  nn
  xnsorts
  xnrels
  xnpreds
  xnops
  xnsens =
  let
    sorts' = Set.map xnWOaToa xnsorts
    rels' = Rel.fromList $ map (\(a,b) -> (xnWOaToa a, xnWOaToa b)) $
      Rel.toList xnrels
    preds' = mapSameIdToSetWith predTypeXNWONToPredType xnpreds
    ops' = mapSameIdToSetWith opTypeXNWONToOpType xnops
    sens' = Set.map xnWOaToa xnsens
  in
    debugGO go "xMTDGNL" "mapsNNToDGNodelab" $
      mapsNNToDGNodeLab go (sorts' , rels' , preds' , ops' , sens' ) nn


{- |
  extracts constructors from adt-structures
-}
-- i need a back-reference to the theory to get presentations for adt-constructors...
extractConsXNWONFromADT::
  FFXInput -- ^ current input settings
  ->AnnXMLN -- ^ wrapped adt 
  ->AnnXMLN -- ^ wrapped theory containing adt
  ->(XmlNamedWONId, [(XmlNamedWONId, OpTypeXNWON)])
extractConsXNWONFromADT ffxi anxml anxmltheory =
  let
    sortdef =
      applyXmlFilter
        (isTag "adt" .> getChildren .> isTag "sortdef")
        (axXml anxml)
    sorts' = xshow $ applyXmlFilter (getValue "name") sortdef
    sortid =
      case findByNameAndOrigin
            sorts'
            (axAnn anxml)
            (mapSetToSet $ xnSortsMap ffxi)
              of
                Nothing -> error "No sort for ADT!"
                (Just si) -> si
    cons = applyXmlFilter (getChildren .> isTag "constructor") sortdef
  in
    (sortid, map (\n -> extractConXNWON [n] sortid) cons)
  where
    extractConXNWON::
      HXT.XmlTrees
      ->XmlNamedWONId
      ->(XmlNamedWONId, OpTypeXNWON) -- empty list on error
    extractConXNWON conx sortid =
      let
        conxname = xshow $ applyXmlFilter (getValue "name") conx
        conhpress = getPresentationString conxname (axXml anxmltheory)
        conid = case conhpress of
                [] -> Hets.stringToId conxname
                _ -> read conhpress
        conxnwonid = XmlNamed (Hets.mkWON conid  (axAnn anxml)) conxname
        args =
          map
            (\n -> xshow [n])
            $
            applyXmlFilter
              (getChildren .> isTag "argument" .> getValue "sort")
              conx
        argsxn =
          map
            (\n -> 
              case findByNameAndOrigin
                    n
                    (axAnn anxml)
                    (mapSetToSet $ xnSortsMap ffxi)
                      of
                        Nothing -> error "Unknown sort in constructor..."
                        (Just x) -> x
            )
            args
      in
        (conxnwonid, OpTypeXNWON Total argsxn sortid)

{- |
  creates sentences from adt-constructors
-}
consToSensXN::
  XmlNamedWONId -- ^ name of the constructed sort
  ->[(XmlNamedWONId, OpTypeXNWON)] -- ^ constructors
  ->XmlNamed Hets.SentenceWO
consToSensXN sortid conlist =
  XmlNamed 
    (Hets.mkWON
      (Ann.NamedSen
        ("ga_generated_" ++ show (xnWOaToa sortid))
        True
        False
        (Sort_gen_ax
          (
          foldl (\constraints (id' , ot) ->
              constraints ++
              [ Constraint
                  (xnWOaToa sortid)
                  [(Qual_op_name
                      (xnWOaToa id' )
                      (Hets.cv_OpTypeToOp_type $ opTypeXNWONToOpType ot)
                      Id.nullRange , [0])] 
                  (xnWOaToa sortid)
              ]
            ) [] conlist
          )
          True
        ))
      (xnWOaToO sortid)
    )
    ("ga_generated_" ++ (xnName sortid))


{- |
  extracts symbols used in a OMDoc-Morphism storing a mapping
  of symbols and a list of hidden symbols
-}
fetchRequationSymbols::HXT.XmlTrees->([String], Hets.RequationList)
fetchRequationSymbols t =
  let
    hides = xshow $ applyXmlFilter (isTag "morphism" .> getQualValue "" "hiding") t
    hiddensyms = breakSepSpace hides
    pattern = isTag "requation" .> processChildren (isTag "OMOBJ") .> getChild 1
    value = isTag "requation" .> processChildren (isTag "OMOBJ") .> getChild 2
    vsymbol = value .> getChildren .> isTag "OMS" .> getQualValue "" "name" 
    psymbol = pattern .> getChildren .> isTag "OMS" .> getQualValue "" "name" 
    vcd = value .> getChildren .> isTag "OMS" .> getQualValue "" "cd" 
    pcd = pattern .> getChildren .> isTag "OMS" .> getQualValue "" "cd" 
    requations = applyXmlFilter (isTag "morphism" .> getChildren .> isTag "requation") t
    reqlist = foldl (\rl ts ->
      let
        psymbolname = xshow $ applyXmlFilter psymbol [ts]
        vsymbolname = xshow $ applyXmlFilter vsymbol [ts]
        pcdname = xshow $ applyXmlFilter pcd [ts]
        vcdname = xshow $ applyXmlFilter vcd [ts]
      in
        if (psymbolname /= []) && (vsymbolname /= [])
          then
            rl ++ [( (pcdname, psymbolname), (vcdname, vsymbolname) )]
          else
            rl
      ) [] requations
  in
    (hiddensyms, reqlist)

getFFXIFor::
  (ImportGraph (HXT.XmlTrees, Maybe (DGraph, FFXInput)))
  ->String
  ->Maybe FFXInput
getFFXIFor
  ig
  theoryname
  =
  let
    withffxi =
      filter
        (\(S _ (_, mdgffxi)) ->
          case mdgffxi of
            Nothing -> False
            _ -> True
        )
        (map snd (Graph.labNodes ig))
    withtheory =
      filter
        (\(S _ (_, (Just (_, ffxi)))) ->
          case
            find
              (\t -> xnName t == theoryname)
              (Set.toList (xnTheorySet ffxi))
          of
            Nothing -> False
            _ -> True
        )
        withffxi
    notref =
      filter
        (\(S _ (_, (Just (dg, ffxi)))) ->
          let
            (nodenum, _) =
              case
                find
                  (\t -> xnName t == theoryname)
                  (Set.toList (xnTheorySet ffxi))
              of
                Nothing -> error "!"
                (Just x) -> xnItem x
            node = Data.Maybe.fromMaybe (error "!") $ Graph.lab dg nodenum
          in
            not $ isDGRef node
        )
        withtheory
  in
    case notref of
      [] -> Nothing
      ((S _ (_, (Just (_, ffxi)))):_) -> Just ffxi
  

{- |
  reconstructs requation symbols used in a OMDoc-Morphism by matching them
  against known sorts, predicates and operators in the source and target sort.
-}
requationSymbolsToIds::
  FFXInput
  ->(ImportGraph (HXT.XmlTrees, Maybe (DGraph, FFXInput)))
  ->String
  ->String
  ->([String], Hets.RequationList)
  ->Hets.MorphismMap
requationSymbolsToIds
  ffxi
  ig
  fromname
  toname
  (hiddensyms, req)
  =
  let
    fromOrigin =
      case
        Set.toList $ Set.filter (\t -> (xnName t) == fromname) (xnTheorySet ffxi)
      of
        [] -> error "no such theory!"
        (o:_) -> fst $ xnItem o
    fromsorts = Set.toList $ Map.findWithDefault Set.empty fromname (xnSortsMap ffxi)
    frompreds = Set.toList $ Map.findWithDefault Set.empty fromname (xnPredsMap ffxi)
    fromops = Set.toList $ Map.findWithDefault Set.empty fromname (xnOpsMap ffxi)
    tosorts = Set.toList $ Map.findWithDefault Set.empty toname (xnSortsMap ffxi)
    topreds = Set.toList $ Map.findWithDefault Set.empty toname (xnPredsMap ffxi)
    toops = Set.toList $ Map.findWithDefault Set.empty toname (xnOpsMap ffxi)
    mappedFSymbols =
      (
        fromsorts
          ++ (map fst frompreds)
          ++ (map fst fromops)
      )
    mappedhidden =
      map
        (\h ->
          xnWOaToa
            $
            fromMaybe
              (XmlNamed (Hets.mkWON (Hets.stringToId h) fromOrigin) h)
              $
              findByName h mappedFSymbols
        )
        hiddensyms
    (sm, pm, om) =
      foldl
        (\(sm', pm', om') ( (fromcd, fromid), (tocd, toid) ) ->
          let
            fsorts =
              fromsorts ++
              if fromcd == fromname
                then
                  []
                else
                  (
                    Set.toList
                      $ Map.findWithDefault Set.empty fromcd (xnSortsMap ffxi)
                  )
                  ++
                  case getFFXIFor ig fromcd of
                    Nothing -> []
                    (Just fromffxi) ->
                      Set.toList $
                        Map.findWithDefault Set.empty fromcd (xnSortsMap fromffxi)
            fpreds =
              frompreds ++
              if fromcd == fromname
                then
                  []
                else
                  (
                    Set.toList
                      $ Map.findWithDefault Set.empty fromcd (xnPredsMap ffxi)
                  )
                  ++
                  case getFFXIFor ig fromcd of
                    Nothing -> []
                    (Just fromffxi) ->
                      Set.toList $
                        Map.findWithDefault Set.empty fromcd (xnPredsMap fromffxi)
            fops =
              fromops ++
              if fromcd == fromname
                then
                  []
                else
                  (
                    Set.toList
                      $ Map.findWithDefault Set.empty fromcd (xnOpsMap ffxi)
                  )
                  ++
                  case getFFXIFor ig fromcd of
                    Nothing -> []
                    (Just fromffxi) ->
                      Set.toList $
                        Map.findWithDefault Set.empty fromcd (xnOpsMap fromffxi)
            tsorts =
              tosorts ++
              if tocd == toname
                then
                  []
                else
                  (
                    Set.toList
                      $ Map.findWithDefault Set.empty tocd (xnSortsMap ffxi)
                  )
                  ++
                  case getFFXIFor ig tocd of
                    Nothing -> []
                    (Just toffxi) ->
                      Set.toList $
                        Map.findWithDefault Set.empty tocd (xnSortsMap toffxi)
            tpreds =
              topreds ++
              if tocd == toname
                then
                  []
                else
                  (
                    Set.toList
                      $ Map.findWithDefault Set.empty tocd (xnPredsMap ffxi)
                  )
                  ++
                  case getFFXIFor ig tocd of
                    Nothing -> []
                    (Just toffxi) ->
                      Set.toList $
                        Map.findWithDefault Set.empty tocd (xnPredsMap toffxi)
            tops =
              toops ++
              if tocd == toname
                then
                  []
                else
                  (
                    Set.toList
                      $ Map.findWithDefault Set.empty tocd (xnOpsMap ffxi)
                  )
                  ++
                  case getFFXIFor ig tocd of
                    Nothing -> []
                    (Just toffxi) ->
                      Set.toList $
                        Map.findWithDefault Set.empty tocd (xnOpsMap toffxi)
            mappedFullFSymbols =
              (
                fsorts
                  ++ (map fst fpreds)
                  ++ (map fst fops)
              )
          in
            case
              findByNameSortPredOp
                fsorts
                fpreds
                fops
                fromid
            of
              (Just (SPOS fs)) ->
                case
                  findByNameSortPredOp
                    tsorts
                    []
                    []
                    toid
                of
                  (Just (SPOS ts)) ->
                    (Map.insert fs ts sm', pm', om')
                  _ ->
                    Debug.Trace.trace
                      ("Error processing Morphism. No Target-Sort-Mapping for \""
                        ++ tocd ++ "#" ++ toid ++ "\""
                      )
                      (sm', pm', om')                    
              (Just (SPOP (fpid, fpt))) ->
                case
                  findByNameSortPredOp
                    []
                    tpreds
                    []
                    toid
                of
                  (Just (SPOP (tpid, tpt))) ->
                    (sm', Map.insert (fpid, fpt) (tpid, tpt) pm', om')
                  _ ->
                    Debug.Trace.trace
                      ("Error processing Morphism. No Target-Predicate-Mapping for \""
                        ++ tocd ++ "#" ++ toid ++ "\""
                      )
                      (sm', pm', om')                    
              (Just (SPOO (foid, fot))) ->
                case
                  findByNameSortPredOp
                    []
                    []
                    tops
                    toid
                of
                  (Just (SPOO (t_oid, tot))) ->
                    (sm', pm', Map.insert (foid, fot) (t_oid, tot) om')
                  _ ->
                    Debug.Trace.trace
                      ("Error processing Morphism. No Target-Operator-Mapping for \""
                        ++ tocd ++ "#" ++ toid ++ "\""
                      )
                      (sm', pm', om')                    
              _ ->
                Debug.Trace.trace
                  ("Error processing Morphism from \"" ++ fromname ++ "\" to \""
                    ++ toname ++ "\" . No Source-Mapping for \""
                    ++ fromcd ++ "#" ++ fromid ++ "\" in " ++ show mappedFullFSymbols
--                    ++ " " ++ show (xnTheorySet ffxi) ++ " " ++ show (xnSortsMap ffxi)
                  )
                  (sm', pm', om')
        )
        (Map.empty, Map.empty, Map.empty)
        req
  in
    (sm, om, pm, Set.fromList mappedhidden)

data SortPredOp = SPOS SORT | SPOP (Id.Id, PredType) | SPOO (Id.Id, OpType)

findByNameSortPredOp::
  [XmlNamedWONSORT]
  ->[(XmlNamedWONId, PredTypeXNWON)]
  ->[(XmlNamedWONId, OpTypeXNWON)]
  ->String
  ->Maybe SortPredOp
findByNameSortPredOp
  xmlnamedsorts
  xmlnamedpreds
  xmlnamedops
  xmlname
  =
    case
      find
        (\xs -> xnName xs == xmlname)
        xmlnamedsorts
    of
      (Just x) ->
        Just (SPOS (xnWOaToa x))
      Nothing ->
        case
          find
            (\(xp, _) -> xnName xp == xmlname)
            xmlnamedpreds
        of
          (Just (xp, xpt)) ->
            Just (SPOP (xnWOaToa xp, predTypeXNWONToPredType xpt))
          Nothing ->
            case
              find
                (\(xo, _) -> xnName xo == xmlname)
                xmlnamedops
            of
              (Just (xo, xot)) ->
                Just (SPOO (xnWOaToa xo, opTypeXNWONToOpType xot))
              Nothing -> Nothing

{-
{- |
  extracts morphisms from xml
-}
xmlToMorphismMap::
  HXT.XmlTrees->
  Hets.MorphismMap
xmlToMorphismMap
  t
  =
  let
    hides = xshow $ applyXmlFilter (isTag "morphism" .> getQualValue "" "hiding") t
    hiddensyms = map Hets.stringToId $ breakSepSpace hides
    pattern = isTag "requation" .> processChildren (isTag "OMOBJ") .> getChild 1
    value = isTag "requation" .> processChildren (isTag "OMOBJ") .> getChild 2
    vsymbol = value .> getChildren .> isTag "OMS" .> getQualValue "" "name" 
    psymbol = pattern .> getChildren .> isTag "OMS" .> getQualValue "" "name" 
    requations = applyXmlFilter (isTag "morphism" .> getChildren .> isTag "requation") t
    sortmap = foldl (\sm ts ->
        case applyXmlFilter (value .> getChildren .> isTag "OMATTR") [ts] of
          [] ->
            let
              psymbolname = xshow $ applyXmlFilter psymbol [ts]
              vsymbolname = xshow $ applyXmlFilter vsymbol [ts]
            in
              if (psymbolname /= []) && (vsymbolname /= [])
                then
                  Map.insert (Hets.stringToId psymbolname) (Hets.stringToId vsymbolname) sm
                else
                  sm
          _ -> sm
      ) Map.empty requations
    (opsmap, predsmap) = foldl (\(om,pm) tp ->
      let
        satp = applyXmlFilter (
          pattern .> getChildren .>
          isTag "OMATTR" .> getChildren .>
          isTag "OMATP") [tp]
        tatp = applyXmlFilter (
          value .> getChildren .>
          isTag "OMATTR" .> getChildren .>
          isTag "OMATP") [tp]
        satpsym = applyXmlFilter (getChildren .> isTag "OMS") satp
        satpstr = applyXmlFilter (getChildren .> isTag "OMSTR") satp
        satpmap = Map.fromList $ zip
          (map (\n -> xshow $ applyXmlFilter (getQualValue "" "name") [n]) satpsym)
          (map (\n -> xshow $ applyXmlFilter (getChildren) [n]) satpstr) 
        tatpsym = applyXmlFilter (getChildren .> isTag "OMS") tatp
        tatpstr = applyXmlFilter (getChildren .> isTag "OMSTR") tatp
        tatpmap = Map.fromList $ zip
          (map (\n -> xshow $ applyXmlFilter (getQualValue "" "name") [n]) tatpsym)
          (map (\n -> xshow $ applyXmlFilter (getChildren) [n]) tatpstr)
        ssymbolname = xshow $ applyXmlFilter (
          pattern .> getChildren .>
          isTag "OMATTR" .> getChildren .> 
          isTag "OMS" .> getValue "name" ) [tp]
        tsymbolname = xshow $ applyXmlFilter (
          value .> getChildren .>
          isTag "OMATTR" .> getChildren .> 
          isTag "OMS" .> getValue "name" ) [tp]
        ssorts = explode "-\\" $ Map.findWithDefault "" "type" satpmap
        tsorts = explode "-\\" $ Map.findWithDefault "" "type" tatpmap
        sOp = OpType
          -- The lookup-mechanism for displaying the morphism needs
          -- 'Partial' entries...
          Partial -- (funKindFromName $ Map.findWithDefault "Total" "funtype" satpmap)
          (map Hets.stringToId ( if (length ssorts) == 1 then [] else init ssorts ))
          (Hets.stringToId $ last ssorts)
        sPred = PredType
          (map Hets.stringToId ssorts)
        tOp =
          OpType
            (funKindFromName $ Map.findWithDefault "Total" "funtype" tatpmap)
            (map Hets.stringToId ( if (length tsorts) == 1 then [] else init tsorts ))
            (Hets.stringToId $ last tsorts)
        tPred =
          PredType
            (map Hets.stringToId tsorts)
      in
        case xshow $ applyXmlFilter (
                        pattern .> getChildren .> 
                        isTag "OMOBJ" .> getChildren .>
                        isTag "OMATTR" .> getChildren .>
                        isTag "OMATP" .> getChildren .>
                        isTag "OMS" .> withSValue "cd" "casl" .>
                        withSValue "name" "funtype" .>
                        getQualValue "" "name") [tp] of
          "funtype" ->
            (Map.insert
              (Hets.stringToId ssymbolname, sOp)
              (Hets.stringToId tsymbolname, tOp)
              om, pm)
          "" ->
            if (ssymbolname /= []) && (tsymbolname /= [])
              then
                (om,
                  Map.insert
                    (Hets.stringToId ssymbolname, sPred)
                    (Hets.stringToId tsymbolname, tPred)
                    pm
                )
              else
                (om, pm)
          x ->
            Debug.Trace.trace ("Unknown Symbol : \"" ++ x ++ "\"") (om,pm)
        ) (Map.empty, Map.empty) requations
  in
          (sortmap, opsmap, predsmap, Set.fromList hiddensyms)
-}

-- | creates a Conservativity from a String or fails with error
stringToConservativity::String->Conservativity
stringToConservativity "None" = None
stringToConservativity "Cons" = Cons
stringToConservativity "Mono" = Mono
stringToConservativity "Def" = Def
stringToConservativity s = error ("Unknown Conservativity : \"" ++ s ++ "\"") 

-- | stringToLinkType returns a list with at most one DGLinkType
-- Unknown links result in empty list
-- Currently this does not work very well because of some formatting issues...
stringToLinkType::String->[DGLinkType]
stringToLinkType s =
  if (length $ words s) == 0
    then
      [] -- error "Cannot determine DGLinkType from empty string!"
    else
      let
        firstword = (words s)!!0
      in
        case firstword of
          "LocalDef" -> [LocalDef]
          "GlobalDef" -> [GlobalDef]
          "HidingDef" -> [HidingDef]
          "LocalThm" ->
            if (length $ words s) < 3
              then
                Debug.Trace.trace
                  ("No data for Conservativity in \"" ++ s ++ "\"")
                  []
              else
                [
                  LocalThm
                    LeftOpen
                    (stringToConservativity $ (words s)!!2)
                    LeftOpen
                ] 
          "GlobalThm" ->
            if (length $ words s) < 3
              then
                Debug.Trace.trace ("No data for Conservativity in \"" ++ s ++ "\"") []
              else
                [
                  GlobalThm
                    LeftOpen
                    (stringToConservativity $ (words s)!!2)
                    LeftOpen
                ]
          "HidingThm" ->
            [HidingThm Hets.emptyCASLGMorphism LeftOpen]
          "FreeDef" ->
            [FreeDef (EmptyNode (Logic.Logic CASL))]
          "CofreeDef" ->
            [CofreeDef (EmptyNode (Logic.Logic CASL))]
          _ ->
            Debug.Trace.trace
              ("Unknown DGLinkType : \"" ++ firstword ++ "\"")
              []
                
defaultDGLinkType::DGLinkType
defaultDGLinkType = GlobalDef

defaultDGOrigin::DGOrigin
defaultDGOrigin = DGExtension

defaultDGLinkLab::DGLinkLab
defaultDGLinkLab =
  DGLink Hets.emptyCASLGMorphism defaultDGLinkType defaultDGOrigin


-- | stringToLink returns a list with at most one DGLinkLab (empty on error)
-- error when string is empty (or whitespace only)
stringToLink::String->[DGLinkLab]
stringToLink s =
  let
    swords = separateFromColonsNoCmt $ wordsWithQuotes s
    ltype = case getFollows (=="Type:") swords of
      Nothing -> ""
      (Just l) -> unquote l
    linktypel = stringToLinkType ltype
    lorigin = case getFollows (=="Origin:") swords of
      Nothing -> ""
      (Just o' ) -> unquote o'
  in
    if (length swords == 0)
      then
        [] -- error "Cannot determine DGLinkLab from empty string!"
      else
        if linktypel == []
          then
            []
          else
            [
              DGLink
                Hets.emptyCASLGMorphism
                (head linktypel)
                (stringToOrigin lorigin)
            ]


-- | separates strings following colons if the string is not quoted
separateFromColonsNoCmt::[String]->[String]
separateFromColonsNoCmt strings =
  separateFromColonsC strings (\s -> (head s) == '"')


-- | separates strings following colons except on strings s where cond s is True        
separateFromColonsC::[String]->(String->Bool)->[String]
separateFromColonsC strings cond =
  foldl (\r s ->
    let 
      parts = explode ":" s
    in
      if cond s
        then
          r ++ [s]
        else
          r ++ if length parts == 1
            then
              parts
            else
              ( (map (++":") (init parts))
                ++
                case (last parts) of
                  "" -> []
                  _ -> [last parts]
              )
    ) [] strings
      
                
getFollows::(a->Bool)->[a]->(Maybe a)
getFollows _ [] = Nothing
getFollows _ [_] = Nothing
getFollows test (first' :second:list) =
  if test first' then (Just second) else getFollows test (second:list)

        
unquote::String->String
unquote [] = []
unquote ('"':rest) = init rest
unquote s = s
  
  
wordsWithQuotes::String->[String]
wordsWithQuotes [] = []
wordsWithQuotes ('"':w) = quote w
  where
    quote::String->[String]
    quote w' =
      ("\""++(takeWhile (/='"') w' )++"\"")
        :(wordsWithQuotes (drop 1 (dropWhile (/='"') w' )))
wordsWithQuotes w =
  let
    word =
      takeWhile
        (\c -> (not $ Char.isSpace c) && (c /= '\"'))
        (dropWhile Char.isSpace w)
    rest =
      dropWhile
        Char.isSpace
        (dropWhile
          (\c -> (not $ Char.isSpace c) && (c /= '\"'))
          (dropWhile Char.isSpace w)
        )
  in
    word:(wordsWithQuotes rest)
          
    

-- remove keys from a map (will result in removing double entries when merging sets)
mapSetToSet::(Ord b)=>Map.Map a (Set.Set b)->Set.Set b
mapSetToSet mapping =
  foldl (\set (_, s) ->
      Set.union set s
    ) Set.empty (Map.toList mapping)
                
-- | convert a map to lists to a map to sets
mapListToMapSet::(Ord b)=>Map.Map a [b]->Map.Map a (Set.Set b)
mapListToMapSet = Map.map Set.fromList


{- |
  AnnotatedXML is a structure containing xml-trees and and annotation
  to these trees.
  Used to have a reference when processing these trees.
-}
data AnnotatedXML a = AXML { axAnn::a, axXml::HXT.XmlTrees }
  deriving Show
        
-- | xml-trees with Graph.Node annotation
type AnnXMLN = AnnotatedXML Graph.Node

-- | equality for AnnotatedXML is determined by equality of annotations
instance (Eq a)=>Eq (AnnotatedXML a) where
  ax1 == ax2 = (axAnn ax1) == (axAnn ax2)

-- | ordering of AnnotatedXML is determined by order of annotations
instance (Ord a)=>Ord (AnnotatedXML a) where
  compare ax1 ax2 = compare (axAnn ax1) (axAnn ax2)

{- |
  An annotated theory set is a set of AnnotatedXML where
  each element in the set contains one theory-tree and is annotated by the
  number of the theory (appearance in file) (pseudo-graph-nodes)
-}
buildAXTheorySet::HXT.XmlTrees->Set.Set AnnXMLN
buildAXTheorySet t =
  let
    theories = applyXmlFilter (getChildren .> isTag "theory") t
  in
    Set.fromList $ zipWith
      (\n t' -> AXML n [t' ])
      [1..]
      theories
                        
{- |
  creates a set of theory names by examining the name of the theory and
  searching for presentation elements.
-}
nodeNamesXNFromXml::Set.Set AnnXMLN->TheoryXNSet
nodeNamesXNFromXml axmlset =
  Set.fromList $ Set.fold
    (\axml txnl ->
      let
        theoid = xshow $ applyXmlFilter (getQualValue "xml" "id") (axXml axml)
        theohetsnodenames = xshow $ applyXmlFilter
          (
            getChildren .> isTag "presentation" .>
            withSValue "for" theoid .> getChildren .>
            isTag "use" .> withSValue "format" "Hets" .>
            getChildren
          ) (axXml axml)
        theohetsnodename =
          if (theohetsnodenames == "") || (isPrefixOf "AnonNode" theoid) 
            then
              idToNodeName $ read ("["++theoid++",,0]")
            else 
              idToNodeName $ read theohetsnodenames
      in
        txnl ++ [XmlNamed ((axAnn axml), theohetsnodename) theoid]
    )
    []
    axmlset

                
sortsXNWONFromXmlTheory::AnnXMLN->(Set.Set XmlNamedWONSORT)
sortsXNWONFromXmlTheory anxml =
  let
    sortnames = map (\m -> xshow [m]) $
      applyXmlFilter
              (
                getChildren .> isTag "symbol" .>
                withQualSValue symbolTypeXMLNS symbolTypeXMLAttr "sort" .>
                getQualValue sortNameXMLNS sortNameXMLAttr
              )
              (axXml anxml)
  in
  Set.fromList $ foldl (\xnss sn ->
    let
      hetspress = xshow $ applyXmlFilter (
        getChildren .> 
        isTag "presentation" .> withSValue "for" sn .>
        getChildren .> isTag "use" .> withSValue "format" "Hets" .>
        getChildren) (axXml anxml)
        -- hets presentations are optional
      hetspres = case hetspress of
        [] -> (Hets.stringToId sn)
        x -> read x -- incorrect hets presentations will cause an exception here
    in
      xnss ++ [ XmlNamed (Hets.mkWON hetspres (axAnn anxml)) sn ]
    ) [] sortnames
                

-- we need annotated xml to define an origin in term of graph-nodes
-- xml-theory-fragments are just nodes in the devgraph...
-- it does not matter if the node-numbers are the same when encoding/decoding
-- they only have to be unique (for the document)
-- the mapping is actually redundancy because the origin of the sort maps to the
-- theory (but this mapping has advantages when looking via XmlName)
sortsXNWONFromXml::TheoryXNSet->Set.Set AnnXMLN->Map.Map XmlName (Set.Set XmlNamedWONSORT)
sortsXNWONFromXml xntheories xmltheoryset =
  Set.fold
    (\anxml tsmap ->
      let
        theosorts = sortsXNWONFromXmlTheory anxml
      in
        if Set.null theosorts
          then
            tsmap
          else
            Map.insert
              (case getTheoryXmlName xntheories (axAnn anxml) of
                Nothing -> error "No Theory!"
                (Just xname) -> xname)
              (sortsXNWONFromXmlTheory anxml)
              tsmap
    )
    Map.empty
    xmltheoryset
    
                
findByName::(Container b (XmlNamed a))=>String->b->Maybe (XmlNamed a)
findByName iname icon =
  find (\i -> (xnName i) == iname) (getItems icon)
        
findAllByNameWithAnd::(Container b a)=>(a->d)->(a->XmlNamed c)->String->b->[d]
findAllByNameWithAnd proc trans iname icon =
  map proc $ filter (\i -> xnName (trans i) == iname) $ getItems icon
  

-- search for a certainly named item and prefer items of specified origin
-- check result for origin if important
findByNameAndOrigin::(Eq b, Container c (XmlNamedWO a b))=>String->b->c->Maybe (XmlNamedWO a b)
findByNameAndOrigin iname iorig icon =
  let
    candidates = filter (\i -> (xnName i) == iname) (getItems icon)
  in
    case find (\i -> (xnWOaToO i) == iorig) candidates of
      Nothing ->
        case candidates of
          (i:_) -> (Just i)
          _ -> Nothing
      i -> i

relsXNWONFromXmlTheory::Set.Set XmlNamedWONSORT->AnnXMLN->Rel.Rel XmlNamedWONSORT
relsXNWONFromXmlTheory xnsortset anxml =
  let
    adts = applyXmlFilter (getChildren .> isTag "adt") (axXml anxml)
    relations = concat $ map relsFromXmlADT adts
  in
    Rel.fromList relations
  where
  relsFromXmlADT::HXT.XmlTree->[(XmlNamedWONSORT, XmlNamedWONSORT)]
  relsFromXmlADT t' =
    let
      xnsorts = xshow $
        applyXmlFilter
          (getChildren .> isTag "sortdef" .>
            withSValue "type" "free" .> getValue "name")
          [t' ]
      xninsortss = map (\n -> drop 1 $ xshow [n]) $
        applyXmlFilter
          (getChildren .> isTag "sortdef" .> getChildren .>
            isTag "insort" .> getValue "for")
          [t' ]
      xnsort = case findByNameAndOrigin xnsorts (axAnn anxml) xnsortset of
        Nothing -> error "Relation for unknown sort!"
        (Just xnsort' ) -> xnsort'
      xninsorts = map (\s -> case findByNameAndOrigin s (axAnn anxml) xnsortset of
        Nothing ->
          Debug.Trace.trace
            ("Relation with unknown sort!" ++ (show s))
            (XmlNamed (Hets.mkWON (Hets.stringToId s) (axAnn anxml)) s)
        (Just xs' ) -> xs'
        ) xninsortss
      -- note that we restore 'CASL-Order' here
    in
      map (\n -> (n, xnsort)) xninsorts
                
        
relsXNWONFromXml::TheoryXNSet->Set.Set XmlNamedWONSORT->Set.Set AnnXMLN->Map.Map XmlName (Rel.Rel XmlNamedWONSORT)
relsXNWONFromXml theoryset xnsortset anxnset =
  Set.fold
    (\axml mapping ->
      let
        theoname = case getTheoryXmlName theoryset (axAnn axml) of
          Nothing -> error "Theory has no name!"
          (Just theoname' ) -> theoname' 
        theorels = relsXNWONFromXmlTheory xnsortset axml
      in
        if Rel.null theorels
          then
            mapping
          else
            Map.insert
              theoname
              theorels
              mapping
      )
    Map.empty
    anxnset


getPresentationString::String->HXT.XmlTrees->String
getPresentationString for t =
  xshow $ applyXmlFilter
    (getChildren .> isTag "presentation" .> withSValue "for" for .>
      getChildren .> isTag "use" .> withSValue "format" "Hets" .> 
      getChildren) t
        

predsXNWONFromXmlTheory::
  Map.Map
    XmlName
    FFXInput
  ->TheoryXNSet
  ->Set.Set XmlNamedWONSORT
  ->AnnXMLN
  ->[(XmlNamedWONId, PredTypeXNWON)]
predsXNWONFromXmlTheory cdmap xntheoryset xnsortset anxml =
  let
    objsymbols = applyXmlFilter (getChildren .> isTag "symbol" .> withQualSValue symbolTypeXMLNS symbolTypeXMLAttr "object") (axXml anxml)
    predsymbols = filter (\n -> applyXmlFilter (
      getChildren .> isTag "type" .>
      getChildren .> isTag "OMOBJ" .>
      getChildren .> isTag "OMA" .>
      getChildren .> isTag "OMS" .>
      withSValue "cd" "casl" .>
      withSValue "name" "predication") [n] /= []) objsymbols
  in
    map predFromXmlSymbol (map (\t -> AXML (axAnn anxml) [t]) predsymbols)
  where
    predFromXmlSymbol::AnnXMLN->(XmlNamedWONId, PredTypeXNWON)
    predFromXmlSymbol panxml =
      let
        pidxname = xshow $
          applyXmlFilter
            (getQualValue predNameXMLNS predNameXMLAttr)
            (axXml panxml)
        pids = getPresentationString pidxname (axXml anxml) -- yes, reference to 'outer' xml
        pid = case pids of
          [] ->
            Debug.Trace.trace
              ("Note: No Hets-Presentation found for Predicate with Xml-ID : \""
                ++ pidxname ++ "\"") $ Hets.stringToId pidxname
          _ -> read pids
        argtags = applyXmlFilter (getChildren .> isTag "type" .>
          withSValue "system" "casl" .> getChildren .> isTag "OMOBJ" .>
          getChildren .> isTag "OMA" .> getChildren .> isTag "OMS" .>
          withValue "name" (/="predication") )
          (axXml panxml)
        argswithcds =
          map
            (\n ->
              (
                xshow $ applyXmlFilter (getValue "name") [n],
                xshow $ applyXmlFilter (getValue "cd") [n]
              )
            )
            argtags
        xnargs =
          map
            (\(axname, acd) ->
              let
                theonode = case getNodeForTheoryName xntheoryset (stripFragment acd) of
                  Nothing -> error "Unknown Theory for Argument!"
                  (Just n) -> n
              in
                case findByNameAndOrigin axname theonode xnsortset of
                  Nothing ->
                    let
                      allffxis = Map.elems cdmap
                      allsortmaps = map xnSortsMap allffxis
                      allsortsets = concat (map Map.elems allsortmaps)
                      allsorts = concat (map Set.toList allsortsets)
                    in
                      case
                        find
                          (\x -> (xnName x) == axname)
                          allsorts
                      of
                        Nothing ->
{-                          error
                            ("Sort " ++ axname ++ " not in FFXI..." ++ show (map xnName allsorts)
                             ++ " at : " ++ (take 300 (xshow (axXml panxml)))
                            ) -}
                          Debug.Trace.trace
                            ("Sort " ++ axname ++ " not in FFXI..." ++ show (map xnName allsorts)
                             ++ " at : " ++ (take 300 (xshow (axXml panxml)))
                            )
                            (XmlNamed (Hets.mkWON (Hets.stringToId axname) theonode) axname)
                        (Just s) ->
--                          Debug.Trace.trace
--                            ("Found sort " ++ axname  ++ " in FFXI...")
                            s
                  (Just xnarg) ->
                    if (xnWOaToO xnarg) /= theonode
                      then
                        Debug.Trace.trace
                          ("Found Argument (" ++ show xnarg ++ ") but in wrong Theory! (not theory #" ++ show theonode ++ ")")
                          xnarg
                      else
                        xnarg
            )
            argswithcds
      in
        (XmlNamed (Hets.mkWON pid (axAnn anxml)) pidxname, PredTypeXNWON xnargs)
        
                        
predsXNWONFromXml::
  Map.Map
    XmlName
    FFXInput
  ->TheoryXNSet
  ->Set.Set XmlNamedWONSORT
  ->Set.Set AnnXMLN
  ->Map.Map XmlName [(XmlNamedWONId, PredTypeXNWON)]
predsXNWONFromXml cdmap xntheoryset xnsortset anxmlset =
  Set.fold
    (\anxml mapping ->
      let
        theopreds = predsXNWONFromXmlTheory cdmap xntheoryset xnsortset anxml
      in
        if null theopreds
          then
            mapping
          else
            Map.insert
              (case getTheoryXmlName xntheoryset (axAnn anxml) of
                      Nothing -> error "Unknown theory!"
                      (Just xname) -> xname
              )
              theopreds
              mapping
    )
    Map.empty
    anxmlset
                

opsXNWONFromXmlTheory::
  Map.Map
    XmlName
    FFXInput
  ->TheoryXNSet
  ->Set.Set XmlNamedWONSORT
  ->AnnXMLN
  ->[(XmlNamedWONId, OpTypeXNWON)]
opsXNWONFromXmlTheory cdmap xntheoryset xnsortset anxml =
  let
    objsymbols = applyXmlFilter (getChildren .> isTag "symbol" .> withQualSValue symbolTypeXMLNS symbolTypeXMLAttr "object") (axXml anxml)
    opsymbols =
      filter
        (\n -> applyXmlFilter (
          getChildren .> isTag "type" .>
          getChildren .> isTag "OMOBJ" .>
          getChildren .> isTag "OMA" .>
          getChildren .> isTag "OMS" .>
          withSValue "cd" "casl" .>
          withValue "name" (\n' -> n' == "function" || n' == "partial-function")
        )
        [n] /= [])
      objsymbols
  in
    map opFromXmlSymbol (map (\n -> AXML (axAnn anxml) [n]) opsymbols) 
  where
    opFromXmlSymbol::AnnXMLN->(XmlNamedWONId, OpTypeXNWON)
    opFromXmlSymbol oanxml =
      let
        oidxname = xshow $
          applyXmlFilter (getQualValue opNameXMLNS opNameXMLAttr) (axXml oanxml)
        oids = getPresentationString oidxname (axXml anxml)
        oid = case oids of
          [] ->
            Debug.Trace.trace ("Note: No Hets-Presentation found for Operator with Xml-ID : \""
              ++ oidxname ++ "\"") $ Hets.stringToId oidxname
          _ -> read oids
        isTotal = applyXmlFilter (
          getChildren .> isTag "type" .> withSValue "system" "casl" .>
          getChildren .> isTag "OMOBJ" .>
          getChildren .> isTag "OMA" .>
          getChildren .> isTag "OMS" .>
          withSValue "name" "function") (axXml oanxml) /= []
        argsalltags = applyXmlFilter (
          getChildren .> isTag "type" .> withSValue "system" "casl" .>
          getChildren .> isTag "OMOBJ" .>
          getChildren .> isTag "OMA" .>
          getChildren .> isTag "OMS" .>
          withValue "name" (\n -> n /= "function" && n /= "partial-function")
          ) (axXml oanxml)
        argsallwithcds =
          map
            (\n ->
              (
                xshow $ applyXmlFilter (getValue "name") [n],
                xshow $ applyXmlFilter (getValue "cd") [n]
              )
            )
            argsalltags
        xnargsall =
          map
            (\(axname, acd) ->
              let
                theonode = case getNodeForTheoryName xntheoryset (stripFragment acd) of
                  Nothing ->
                    Debug.Trace.trace
                      ("No Theory for Argument! " ++ (stripFragment acd) ++ "#" ++ axname)
                      (-1)
                  (Just n) -> n
              in
                case findByNameAndOrigin axname theonode xnsortset of
                  Nothing ->
                    let
                      allffxis = Map.elems cdmap
                      allsortmaps = map xnSortsMap allffxis
                      allsortsets = concat (map Map.elems allsortmaps)
                      allsorts = concat (map Set.toList allsortsets)
                    in
                      case
                        find
                          (\x -> (xnName x) == axname)
                          allsorts
                      of
                        Nothing ->
                          Debug.Trace.trace
                            ("Sort " ++ axname ++ " not in FFXI..." ++ show (map xnName allsorts)
                             ++ " at : " ++ (take 300 (xshow (axXml oanxml)))
                            )
                            (XmlNamed (Hets.mkWON (Hets.stringToId axname) theonode) axname)
                        (Just s) ->
--                          Debug.Trace.trace
--                            ("Found sort " ++ axname  ++ " in FFXI...")
                            s
                  (Just xnarg) -> if (xnWOaToO xnarg) /= theonode
                    then
                      Debug.Trace.trace
                        ("Found Argument (" ++ show xnarg ++ ") but in wrong Theory! (not in theory #" ++ show theonode ++ ")")
                        xnarg
                    else
                      xnarg
            )
            argsallwithcds
        xnargs = take (length(xnargsall)-1) xnargsall
        xnres = last (xnargsall)
      in
        (
          XmlNamed (Hets.mkWON oid (axAnn anxml)) oidxname,
            OpTypeXNWON
                    (if isTotal then Total else Partial)
                    xnargs
                    xnres
        )


opsXNWONFromXml::
  Map.Map
    XmlName
    FFXInput
  ->TheoryXNSet
  ->Set.Set XmlNamedWONSORT
  ->Set.Set AnnXMLN
  ->Map.Map XmlName [(XmlNamedWONId, OpTypeXNWON)]
opsXNWONFromXml cdmap xntheoryset xnsortset anxmlset =
  Set.fold
    (\anxml mapping ->
      let
        theoops = opsXNWONFromXmlTheory cdmap xntheoryset xnsortset anxml
      in
        if null theoops
          then
            mapping
          else
            Map.insert
              (case getTheoryXmlName xntheoryset (axAnn anxml) of
                Nothing -> error "Unknown theory!"
                (Just xname) -> xname
              )
              theoops
              mapping
    ) Map.empty anxmlset
                                                

-- | imports lead to edges but if the information is not stored in the
-- document there is no clue on what type of edge to create...
data ImportHint = FromStructure (String, DGLinkLab) | FromData (String, DGLinkLab)
  deriving (Eq, Show)
        
fromName::ImportHint->String
fromName (FromStructure (s,_)) = s
fromName (FromData (s, _)) = s

getIHLink::ImportHint->DGLinkLab
getIHLink (FromStructure (_,l)) = l
getIHLink (FromData (_,l)) = l

-- simple ord-relation to make Set happy...     
instance Ord ImportHint where
  (FromStructure _) <= (FromStructure _) = True
  (FromStructure _) <= (FromData _) = True
  (FromData _) <= (FromData _) = True
  (FromData _) <= (FromStructure _) = False
        

-- | create information about the imports from the private fields...
createImportHints::HXT.XmlTrees->(Map.Map String (Set.Set ImportHint))
createImportHints t =
  let
    privates = applyXmlFilter (isTag "private") t
    theonames = map (\n -> xshow [n]) $ applyXmlFilter (getQualValue "" "for") privates
  in
    foldl
      (\hints name' ->
        let
          pdata = xshow $ applyXmlFilter (
            withSValue "for" name' .> getChildren .>
            isTag "data" .> withSValue "pto" "Hets" .>
            withSValue "format" "Hets-Imports" .> getChildren) privates
          ldata = lines pdata
        in
          if ldata == []
            then -- empty lines create no hints...
              hints
            else
              foldl
                (\h l ->
                  let
                    lablink = stringToLink l
                    fromname = case getFollows
                      (=="From:")
                      (separateFromColonsNoCmt $ wordsWithQuotes l)
                        of
                          Nothing -> ""
                          (Just n) -> unquote n
                  in
                    if l == []
                      then
                        h -- empty lines create no hints...
                      else
                        if lablink == []
                          then -- error processing the line -> still create structure hint...
                            Map.insert
                              name'
                              (Set.union
                                (Map.findWithDefault Set.empty name' h)
                                (Set.singleton
                                  (FromStructure (fromname, defaultDGLinkLab)) )
                              )
                              h
                          else -- create a hint with the parsed lablink
                          Map.insert
                            name'
                            (Set.union
                              (Map.findWithDefault Set.empty name' h)
                              (Set.singleton (FromData (fromname, (head lablink))))
                            )
                            h
                )
                hints
                ldata
      ) Map.empty theonames

-- | extracts global and local theorem links from axiom- and theory-inclusion
-- tags. Returns a list of (inclusion-id, from, to, DGLinkLab).
glThmsFromXml::
  FFXInput
  ->(ImportGraph (HXT.XmlTrees, Maybe (DGraph, FFXInput)))
  ->HXT.XmlTrees
  ->[(XmlName, XmlName, XmlName, DGLinkLab)]
glThmsFromXml ffxi ig t =
  let
    inclusions =
      applyXmlFilter (isTag "theory-inclusion" +++ isTag "axiom-inclusion") t
  in
    foldl (\glts inx ->
      let
        islocal = null $ applyXmlFilter (isTag "theory-inclusion") [inx]
        incons = consFromAttr [inx]
        inid = xshow $ applyXmlFilter (getQualValue "xml" "id") [inx]
        infrom = xshow $ applyXmlFilter (getQualValue "" "from") [inx]
        infromid =
          case infrom of
            ('#':r) -> r
            _ -> infrom
        into = xshow $ applyXmlFilter (getQualValue "" "to") [inx]
        intoid =
          case into of
            ('#':r) -> r
            _ -> into
        inmorphx = applyXmlFilter (getChildren .> isTag "morphism") [inx]
        -- inmorph = case inmorphx of [] -> []; _ -> [xmlToMorphismMap inmorphx]
        inmorph = case inmorphx of [] -> []; _ -> [fetchRequationSymbols inmorphx]
        caslGMorph = case inmorph of
          [morphismMap] ->
--            Hets.makeCASLGMorphism $ Hets.morphismMapToMorphism morphismMap
            Hets.makeCASLGMorphism
              $
              Hets.morphismMapToMorphism
                $
                requationSymbolsToIds
                  ffxi
                  ig
                  infromid
                  intoid
                  morphismMap
          _ ->
            Hets.emptyCASLGMorphism
      in
        glts ++
          [
            (  inid
              ,infrom
              ,into
              ,DGLink
                {
                   dgl_morphism = caslGMorph
                  ,dgl_type =
                    (if islocal then LocalThm else GlobalThm)
                      LeftOpen
                      incons
                      LeftOpen
                  ,dgl_origin = DGBasic
                }
            )
          ]
      )
      []
      inclusions
  where
  consFromAttr::HXT.XmlTrees->Conservativity
  consFromAttr t' =
    let
      consattr = xshow $ applyXmlFilter (getValue "conservativity") t'
    in
      case consattr of
        "monomorphism" -> Mono
        "conservative" -> Cons
        "definitional" -> Def
        _ -> None

-- used by new format (for import graph)
importsFromXmlTheory::HXT.XmlTrees->Hets.Imports
importsFromXmlTheory t =
  let
    imports' = applyXmlFilter (getChildren .> isTag "imports") t
  in
    foldl
      (\imps (c, i) ->
        let
          from = xshow $ applyXmlFilter (getValue "from") [i]
          mfromURI = URI.parseURIReference from
          fromname = case mfromURI of
            Nothing -> from
            (Just uri) -> case URI.uriFragment uri of
                    "" -> from
                    f -> drop 1 f
          xmorph = applyXmlFilter (getChildren .> isTag "morphism") [i]
          hreq = fetchRequationSymbols xmorph
          -- mm = xmlToMorphismMap xmorph
          -- there is at most one morphism for each import...
{-          mm = foldl (\(mmsm, mmfm, mmpm, mmhs) m ->
              let
                (nmmsm, nmmfm, nmmpm, nmmhs) = xmlToMorphismMap [m]
                hreq = fetchRequationsSymbols [m]
              in
                (Map.union mmsm nmmsm,
                  Map.union mmfm nmmfm, Map.union mmpm nmmpm,
                    Set.union mmhs nmmhs)
            ) (Map.empty, Map.empty, Map.empty, Set.empty) $
              applyXmlFilter (getChildren .> isTag "morphism") [i] -}
        in
          Set.union imps (Set.singleton (c, (fromname, {-(Just mm)-} Nothing, hreq, True)))
      ) Set.empty (zip [1..] imports')
       
-- used in edge contstruction
importsFromXml::HXT.XmlTrees->Hets.ImportsMap
importsFromXml t =
  foldl (\map' theory ->
    let
      name' = xshow $ applyXmlFilter (getQualValue "xml" "id") [theory]
      imports' = importsFromXmlTheory [theory]
    in
      Map.insert name' imports' map'
    ) Map.empty $ applyXmlFilter (isTag "theory") t

                
sensXNWONFromXmlTheory::FFXInput->AnnXMLN->(Set.Set (XmlNamed Hets.SentenceWO))
sensXNWONFromXmlTheory ffxi anxml =
  Set.fromList $ unwrapFormulasXNWON ffxi anxml
        

sensXNWONFromXml::
  GlobalOptions
  ->FFXInput
  ->Set.Set AnnXMLN
  ->Map.Map XmlName (Set.Set (XmlNamed Hets.SentenceWO))
sensXNWONFromXml go ffxi anxmlset = 
  (\smap ->
    debugGO go "sXNWONFX" ("AllSentences : " ++ (showSenNames smap)) smap) $!
      Set.fold (\anxml map' ->
        let
          theoryname = case getTheoryXmlName (xnTheorySet ffxi) (axAnn anxml) of
            Nothing -> error "No theory found!"
            (Just tn) -> tn
          sens = sensXNWONFromXmlTheory ffxi anxml
          consens = conSensXNWONFromXmlTheory ffxi anxml
        in
          (\smap ->
            debugGO go "sXNWONFX" ("NewSentences : " ++ (showSenSetNames sens)
              ++ " - ConSentences : " ++ (showSenSetNames consens)) smap) $
                Map.insert theoryname (Set.union sens consens) map'
        ) Map.empty anxmlset
                

conSensXNWONFromXmlTheory::FFXInput->AnnXMLN->Set.Set (XmlNamed Hets.SentenceWO) 
conSensXNWONFromXmlTheory ffxi anxml =
  let
    adts = applyXmlFilter (getChildren .> isTag "adt") (axXml anxml)
  in
    Set.fromList $ foldl
      (\list n ->
        let
          (excon, exconlist) =
            extractConsXNWONFromADT ffxi (AXML (axAnn anxml) [n]) anxml
        in
          if (length exconlist) == 0 -- if only the relation is expressed,
                                     -- no constructors are specified
            then
              list
            else
              list ++ [consToSensXN excon exconlist] 
      ) [] adts 

mapsToG_theory::
  (
      Set.Set SORT
    , Rel.Rel SORT
    , Map.Map Id.Id (Set.Set PredType)
    , Map.Map Id.Id (Set.Set OpType)
    , Set.Set (Ann.Named CASLFORMULA)
  )
  ->G_theory
mapsToG_theory (sortset, rels' , predmap, opmap, sensmap) =
  G_theory
          CASL
          (Sign
            sortset
            rels'
            opmap
            Map.empty
            predmap
            Map.empty
            []
            []
            GA.emptyGlobalAnnos
            ()
          ) 
          (Prover.toThSens $ Set.toList sensmap)
                
-- Prover.toThSens creates named sentences on its own... trouble for xml...

                
mapsNNToDGNodeLab::
  GlobalOptions
  ->(
      Set.Set SORT
    , Rel.Rel SORT
    , Map.Map Id.Id (Set.Set PredType)
    , Map.Map Id.Id (Set.Set OpType)
    , Set.Set (Ann.Named CASLFORMULA)
    )
  ->NODE_NAME
  ->DGNodeLab
mapsNNToDGNodeLab go maps@(_, _, _, _, sens) nodename =
  DGNode
    nodename
    ((\x ->
      debugGO go "mNNTDGNL" ((show (Set.map Ann.senName sens))
        ++ " -> "
          ++ (show (map Ann.senName (Hets.getSentencesFromG_theory x)))) x
     ) (mapsToG_theory maps)
    )
    Nothing
    Nothing
    DGBasic
    None
    LeftOpen

                
showSenSetNames::Set.Set (XmlNamed Hets.SentenceWO)->String
showSenSetNames senset =
  let
    senlist = Set.toList senset
    sennamesx = map (\s -> (Ann.senName $ xnWOaToa s, xnName s)) senlist
    senstrings = map (\(a, b) -> a ++ "(" ++ b ++ ")") sennamesx
  in
    implode ",    " senstrings
                
showSenNames::Map.Map XmlName (Set.Set (XmlNamed Hets.SentenceWO))->String
showSenNames mapping =
  let
    sensets = Map.elems mapping
    senlist = concatMap Set.toList sensets
    sennamesx = map (\s -> (Ann.senName $ xnWOaToa s, xnName s)) senlist
    senstrings = map (\(a, b) -> a ++ "(" ++ b ++ ")") sennamesx
  in
    implode ", " senstrings

importGraphToDGNodesXN::
  GlobalOptions
  ->(ImportGraph (HXT.XmlTrees, Maybe (DGraph, FFXInput)))
  ->Graph.Node->([XmlNamed DGNodeLab], Set.Set AnnXMLN, FFXInput)
importGraphToDGNodesXN go ig n =
  let
    mnode = Graph.lab ig n
    node = case mnode of
      Nothing -> error "node error!"
      (Just n') -> n'
    refimports = (\x ->
      debugGO go "iGTDGNXN" ("Refimports : " ++ show x) x) $
        filter ( \(_,from,_) -> from /= n) $ Graph.out ig n
    cdmap =
      foldl (\cm (_, from, (TI (theoname, _))) ->
        let
          moriginnode = Graph.lab ig from
          (S (slibname, _) (_,modg)) = case moriginnode of
            Nothing -> error ("node error (Import of "
              ++ theoname ++ " from " ++ (show from) ++ " )!")
            (Just n' ) -> n'
            -- the DG should have been created before accessing it (should work)
          (odg, offxi) = case modg of
                  Nothing -> error ("dg error (DevelopmentGraph for "
                    ++ slibname ++ " not found)!")
                  (Just o) -> o
          theoid =
            case
              find
                (\q -> xnName q == theoname)
                (Set.toList (xnTheorySet offxi))
            of
              Nothing -> theoname
              (Just q) -> showName $ snd $ xnItem q 
          ({-onodenum-}_, onodedgnl) =
            case filter
              (\(_,node' ) -> (getDGNodeName node' ) == theoid ) $
              Graph.labNodes odg
                of
                  [] -> error ("no such node in origin... 1 (for " ++ theoname ++ ")")
                  l -> head l
          otxn =
            case
              find
                (\xno -> (snd $ xnItem xno) == (dgn_name onodedgnl))
                  $ Set.toList (xnTheorySet offxi)
                of
              Nothing -> error ("No Entry for this node in the theories ffxi!")
              (Just xno) -> xno
          oxn = xnName otxn
{-          otss = Map.findWithDefault Set.empty oxn (xnSortsMap offxi)
          otsr = Map.findWithDefault Rel.empty oxn (xnRelsMap offxi)
          otps = Map.findWithDefault Set.empty oxn (xnPredsMap offxi)
          otos = Map.findWithDefault Set.empty oxn (xnOpsMap offxi)
          cmv = (otss, otsr, otps, otos) -}
        in
          (Map.insert oxn offxi cm)
        ) Map.empty refimports
    (ffxi, axtheoryset) =
      (\(f, a) -> debugGO go "iGTDGNXN" ("Preprocessed XML..." ++ show (xnSortsMap f)) (f, a) ) $
        (\(S _ (omdoc' , _)) -> preprocessXml go cdmap omdoc' ) node
    (theonames, sortsmap, relsmap, predsmap, opsmap) =
      (xnTheorySet ffxi, xnSortsMap ffxi,
        xnRelsMap ffxi, xnPredsMap ffxi, xnOpsMap ffxi)
    (refs, newffxi) =
      foldl (\(r, nf) (_, from, (TI (theoname, _))) ->
        let
          moriginnode = Graph.lab ig from
          (S (slibname, _) (_,modg)) = case moriginnode of
            Nothing -> error ("node error (Import of "
              ++ theoname ++ " from " ++ (show from) ++ " )!")
            (Just n' ) -> n'
            -- the DG should have been created before accessing it (should work)
          (odg, offxi) = case modg of
                  Nothing -> error ("dg error (DevelopmentGraph for "
                    ++ slibname ++ " not found)!")
                  (Just o) -> o
          theonodename =
            case
              find
                (\q -> xnName q == theoname)
                (Set.toList (xnTheorySet offxi))
            of
              Nothing -> (Hets.stringToSimpleId theoname, "", 0)
              (Just q) -> snd $ xnItem q 
          (onodenum, onodedgnl) =
            case filter
              (\(_,node' ) -> dgn_name node' == theonodename ) $
              Graph.labNodes odg
                of
                  [] -> error ("no such node in origin... (for \"" ++ theoname ++ "\")")
                  l -> head l
          otxn =
            case
              find
                (\xno -> (snd $ xnItem xno) == (dgn_name onodedgnl))
                  $ Set.toList (xnTheorySet offxi)
                of
              Nothing -> error ("No Entry for this node in the theories ffxi!")
              (Just xno) -> xno
          oxn = xnName otxn
          otss = Map.findWithDefault Set.empty oxn (xnSortsMap offxi)
          otsr = Map.findWithDefault Rel.empty oxn (xnRelsMap offxi)
          otps = Map.findWithDefault Set.empty oxn (xnPredsMap offxi)
          otos = Map.findWithDefault Set.empty oxn (xnOpsMap offxi)
          nf' =
            nf
              {
                  xnTheorySet = Set.union (xnTheorySet nf) (Set.singleton otxn)
                , xnSortsMap = Map.insertWith Set.union oxn otss (xnSortsMap nf)
                , xnRelsMap = Map.insertWith Rel.union oxn otsr (xnRelsMap nf)
                , xnPredsMap = Map.insertWith Set.union oxn otps (xnPredsMap nf)
                , xnOpsMap = Map.insertWith Set.union oxn otos (xnOpsMap nf)
              }
        in
          (
            r ++
              [
              XmlNamed
                (DGRef
                  -- (Hets.stringToSimpleId theoname, "", 0)
                  theonodename
                  (ASL.Lib_id (ASL.Indirect_link slibname Id.nullRange))
                  onodenum
                  --(G_theory CASL Hets.emptyCASLSign (Prover.toThSens []))
                  (dgn_theory onodedgnl)
                  Nothing
                  Nothing)
                theoname
              ]
            , nf'
          )
        ) ([],ffxi) refimports
    -- when extracting sentences, available sorts in the theory have to be computed...
    -- (not yet done)
{-    sensmap = (\smap ->
      debugGO go "iGTDGNXN" ("Sentences extracted... : "
        ++ (showSenNames smap)) smap) $ sensXNWONFromXml go (debugGO go "iGTDGNXN" ("sorts : " ++ show (xnSortsMap newffxi)) newffxi) axtheoryset -}
    -- sensmap = Map.empty
    -- psorts = mapSetToSet (debugGO go "iGTDGNXN" "at mapSetToSet(sortsmap)" sortsmap)
    -- ppreds = mapSetToSet (debugGO go "iGTDGNXN" "at mapSetToSet(predsmap)" predsmap)
    -- pops = mapSetToSet (debugGO go "iGTDGNXN" "at mapSetToSet(opsmap)" opsmap)
  in   
    (\a -> (a, axtheoryset, newffxi)) $
    Set.fold (\xntheory dgnodelist ->
      let
        tsorts = Map.findWithDefault Set.empty (xnName xntheory) sortsmap
        trels = Map.findWithDefault Rel.empty (xnName xntheory) relsmap
        tpreds = Map.findWithDefault Set.empty (xnName xntheory) predsmap
        tops = Map.findWithDefault Set.empty (xnName xntheory) opsmap
        -- tsens = Map.findWithDefault Set.empty (xnName xntheory) sensmap
      in
        debugGO go "iGTDGNXN" ("Creating Node with NODE_NAME "
          ++ (show (snd (xnItem xntheory))) ++ ", XmlName was "
            ++ (xnName xntheory))
          (dgnodelist
            ++ [XmlNamed
                  (xnMapsToDGNodeLab
                    go
                    (snd (xnItem xntheory)) tsorts trels tpreds tops Set.empty)
                  (xnName xntheory)
               ])
      ) refs (debugGO go "iGTDGNXN" "at Set.fold" theonames)
  

cleanNodeName::DGNodeLab->DGNodeLab
cleanNodeName (node@(DGNode { })) =
  if isPrefix "AnonNode" (getDGNodeName node)
    then
      node { dgn_name = emptyNodeName }
    else
      node
cleanNodeName ref = ref

-- build a DGraph-'skeleton' and attach hiding-information
importGraphToDGraphXN::
  GlobalOptions
  ->(ImportGraph (HXT.XmlTrees, Maybe (DGraph, FFXInput)))
  ->Graph.Node
  ->(DGraph, Map.Map Graph.Node XmlName, FFXInput, Set.Set AnnXMLN)
importGraphToDGraphXN go ig n =
  let
    mnode = Graph.lab ig n
    node = case mnode of
      Nothing -> error "node error!"
      (Just n') -> n'
    omdoc = (\(S _ (omdoc' , _)) ->
      applyXmlFilter (isTag "omdoc" .> getChildren) omdoc' ) node
    -- I have not yet found the source for the initial reversion...
    -- Output is a candidate...
    -- FFXInput was intended to rename symbols in formulas but this needs to
    -- be done for morphisms also (and the structure is created anyway)
    (nodes, axtheoryset, ffxi) =
      (\(a, b, c) -> (reverse a, b, c))
        $
        importGraphToDGNodesXN go ig n
    lnodes = (zip [0..] nodes)::[(Graph.Node, (XmlNamed DGNodeLab))]
    --nodegraph = (Graph.mkGraph lnodes [])::DGraph
{-    nameNodeMap = Map.fromList $
      map ( \(n' , xnnode' ) -> (getDGNodeName (xnItem xnnode' ) , n' ) ) $ lnodes -}
    nodeXNameMap = Map.fromList $
      map (\(n', xnnode' ) -> (n', xnName xnnode')) lnodes
    xmlnameNodeMap = Map.fromList $
      map ( \(n' , xnnode' ) -> (xnName xnnode', n' ) ) $ lnodes
    imports' = importsFromXml omdoc
    importhints = createImportHints omdoc
    glTheoIncs = glThmsFromXml ffxi ig omdoc
    glThmLEdges =
      foldl
        (\gltle (_, efrom, eto, lnk) ->
          let
            fromname = getFragmentOrWarnAndString efrom
            toname = getFragmentOrWarnAndString eto
            fromnum = Map.findWithDefault (-1) fromname xmlnameNodeMap
            tonum = Map.findWithDefault (-1) toname xmlnameNodeMap
          in
            gltle ++ [ (fromnum, tonum, lnk) ]
        )
        []
        glTheoIncs
    ledges =
      foldl
        (\le (nodename, nodeimports) ->
          let     
            nodenum = Map.findWithDefault (-1) nodename xmlnameNodeMap
            nodeimporthints = Map.findWithDefault Set.empty nodename importhints
            importsfrom = map (\(_, (a,_,_,_)) -> a) $ Set.toList nodeimports
            -- the omdoc-imports have limited support for the imports
            -- used in a dgraph. some import-hints have no import-tag in
            -- the omdoc
            importhintswithoutimports =
              Set.filter
                (\ih ->
                  (not $ elem (fromName ih) importsfrom)
                    &&
                      (case (Static.DevGraph.dgl_type (getIHLink ih)) of
                        -- filter out private data that is already covered by omdoc
                        -- (kind of backward-compatibility, but not really)
                        (LocalDef {}) -> False
                        (GlobalDef {}) -> False
                        (HidingDef {}) -> False
                        (LocalThm {}) -> False
                        (GlobalThm {}) -> False
                        (HidingThm {}) -> False
                        _ -> True
                      )
                )
                nodeimporthints 
          in
            (foldl (\le' (_, (ni, {-mmm-}_, hreq, isGlobal)) ->
              let
                importnodenum = case Map.findWithDefault (-1) ni xmlnameNodeMap of
                  (-1) ->
                    debugGO
                      go
                      "iGTDGXN"
                      ("Cannot find node for \"" ++ ni ++ "\"!")
                      (-1)
                  x -> x
                filteredimporthints =
                  Set.filter (\h -> (fromName h) == ni) importhintswithoutimports
                hreqmm@(_,_,_,hidingSet) =
                 requationSymbolsToIds
                  ffxi
                  ig
                  ni
                  nodename
                  hreq
                hreqmorph =
                  (Hets.morphismMapToMorphism hreqmm)
                hreqgmorph = 
                  Hets.makeCASLGMorphism hreqmorph
                isHiding = not $ Set.null hidingSet
                ddgl =
                  (if isGlobal
                    then 
                      if isHiding
                        then
                          defaultDGLinkLab { dgl_type = Static.DevGraph.HidingDef }
                        else
                          defaultDGLinkLab
                    else
                      defaultDGLinkLab { dgl_type = Static.DevGraph.LocalDef }
                  ) {
                        dgl_morphism = hreqgmorph
                      , dgl_origin =
                        if Hets.isEmptyMorphism hreqmorph
                          then
                            dgl_origin defaultDGLinkLab
                          else
                            DGTranslation
                    }
              in
                le' ++
                if Set.null filteredimporthints
                  then
                    [(importnodenum, nodenum, ddgl)]
                  else
                    map
                      (\ih ->
                        let
                          ihlink = getIHLink ih
                          link = case dgl_origin ihlink of
                          -- this is rather ugly, but else morphisms would be lost for now...
                            DGTranslation ->
                              ihlink { dgl_morphism = dgl_morphism ddgl }
                            DGHiding ->
                              ihlink { dgl_morphism = dgl_morphism ddgl }
                            _ -> ihlink
                        in
                          (importnodenum, nodenum, link)
                      ) $ Set.toList filteredimporthints
            ) le $ Set.toList nodeimports)
            -- add further imports
            ++
            (map
              (\ih ->
                let
                  ni = fromName ih
                  importnodenum = case Map.findWithDefault (-1) ni xmlnameNodeMap of
                          (-1) ->
                            debugGO
                              go
                              "iGTDGXN"
                              ("Cannot find node for \"" ++ ni ++ "\"!")
                              (-1)
                          x -> x
                in
                  (importnodenum, nodenum, getIHLink ih)
              ) $
              (\x ->
                debugGO go "iGTDGXNimporthints"
                  ("Importhints: " ++ (show x)) x ) $
                  Set.toList importhintswithoutimports
            )
        ) [] $ Map.toList imports'
    validedges = foldl (\e newe@(n', m, _) ->
      if (n' ==(-1)) || (m==(-1))
        then
          debugGO go "iGTDGXN"
            ("Invalid Edge found from " ++ (show n' )
              ++ " to " ++ (show m) ++ "...")
            e
        else
          e++[newe]
        ) [] (ledges ++ glThmLEdges)
    cleannodes =
      map
        (\(n' , xnnode' ) -> (n' , cleanNodeName (xnItem xnnode' ) ))
        lnodes  
  in
    (Graph.mkGraph cleannodes validedges, nodeXNameMap, ffxi, axtheoryset)
  where
  getFragmentOrWarnAndString::String->String
  getFragmentOrWarnAndString s =
    case URI.parseURIReference s of
      Nothing ->
        Debug.Trace.trace
          ("Please use valid URIs for local or global theorem inclusions."
            ++ "Using \"" ++ s ++ "\".")
          s
      (Just anuri) ->
        let
          frag = URI.uriFragment anuri
        in
          if (length frag < 2 )
            then
              Debug.Trace.trace
                ("Please specify a fragment referencing the theory for "
                  ++ "local or global theorem inclusions. Using \""
                    ++ s ++ "\".")
                s
            else
              drop 1 frag

type TaggedEdgeDGraph = CLGraph.Gr DGNodeLab (Int, DGLinkLab)

tagEdges::DGraph->TaggedEdgeDGraph
tagEdges dg =
  let
    labNodes = Graph.labNodes dg
    labEdges = Graph.labEdges dg
    newLabEdges = zipWith (\a (f, t, dgl) -> (f, t, (a, dgl))) [1..] labEdges
  in
    Graph.mkGraph labNodes newLabEdges

untagEdges::TaggedEdgeDGraph->DGraph
untagEdges tedg =
  let
    labNodes = Graph.labNodes tedg
    labEdges = Graph.labEdges tedg
    newLabEdges = map (\(f, t, (_, dgl)) -> (f, t, dgl)) labEdges
  in
    Graph.mkGraph labNodes newLabEdges

processImportsAndMorphisms::DGraph->Map.Map Graph.Node XmlName->FFXInput->(DGraph, FFXInput)
processImportsAndMorphisms dg nxm ffxi =
  let
    taggedDG = tagEdges dg
    allEdges = (Graph.labEdges taggedDG)
    defEdges =
      foldl
        (\eC (tedge@(_,_,(_, dgl))) ->
          eC ++
            case dgl_type dgl of
              (GlobalDef {}) -> [tedge] 
              (LocalDef {}) -> [tedge]
              (HidingDef {}) -> [tedge]
              (FreeDef {}) -> [tedge]
              (CofreeDef {}) -> [tedge]
              _ -> []
        )
        []
        allEdges
    thmEdges =
      foldl
        (\eC (tedge@(_,_,(_, dgl))) ->
          eC ++
            case dgl_type dgl of
              (GlobalThm {}) -> [tedge] 
              (LocalThm {}) -> [tedge]
              (HidingThm {}) -> [tedge]
              _ -> []
        )
        []
        allEdges 
    ((defdg, defffxi), _, _) =
      until
        (\(_, remainingEdges, _) -> null remainingEdges)
        (\((dg', ffxi'), (edge:edges), fc) ->
   --       Debug.Trace.trace (".") $
            processEdge fc dg' nxm ffxi' edge edges
        )
        ((taggedDG, ffxi), defEdges, 0)
    ((thmdg, thmffxi), _, _) =
      until
        (\(_, remainingEdges, _) -> null remainingEdges)
        (\((dg', ffxi'), (edge:edges), fc) ->
   --       Debug.Trace.trace (".") $
            processEdge fc dg' nxm ffxi' edge edges
        )
        ((defdg,defffxi), thmEdges, 0)
  in
      (untagEdges thmdg, thmffxi)

processEdge::
    Int
  ->TaggedEdgeDGraph
  ->Map.Map Graph.Node XmlName
  ->FFXInput
  ->Graph.LEdge (Int, DGLinkLab)
  ->[Graph.LEdge (Int, DGLinkLab)]
  ->((TaggedEdgeDGraph, FFXInput), [Graph.LEdge (Int, DGLinkLab)], Int)
processEdge
  failcount
  tdg
  nxm
  ffxi
  (tedge@(from, to, ({-tag-}_, dgl)))
  edges =
  -- check if this edge is from a node that needs edge processing itself
  -- if yes : process that node recusivly, else : apply import
  -- local imports are always valid, unless they contain a morphism
  -- if they contain a morphism, process last (two (depending) morphisms need
  -- to be processed according to order (need info from previous step... not possible
  -- here..., but when independent, processing is possible)
  --
  let
    -- fromnode = fromMaybe (error "No such node!") $ Graph.lab tdg from
    -- tonode = fromMaybe (error "No such node!") $ Graph.lab tdg to
    unprocessedFrom = filter (\(from', tof, _) -> (from' /= from) && (tof == from) ) edges
    fromxname = Map.findWithDefault (error "No such name!") from nxm
    toxname = Map.findWithDefault (error "No such name!") to nxm
    (parallelImports, otherImports) =
      partition (\(_, tot, _) -> tot == to) edges
  in
    if null unprocessedFrom
      then
        if hasCASLMorphism dgl
          then
            case partition (\(_, _, (_, dgl')) -> not $ hasCASLMorphism dgl') parallelImports
            of
              ( [], _ ) ->
    --            Debug.Trace.trace ("M!")
                  ( applyLink tdg tedge, edges, 0)
              ( betterEdges, rest ) ->
                if failcount > 50
                  then
                    Debug.Trace.trace
                      ("Forced decision in link application from "
                        ++ fromxname ++ " to " ++ toxname ++ "!") 
                      ( applyLink tdg tedge, edges, 0)
                  else
{-                    Debug.Trace.trace
                      (
                        "BeboM " ++ show (fromxname, toxname) 
                          ++ show (length betterEdges) 
                          ++ " " ++ show (length rest)  
                      ) -}
                      ((tdg, ffxi), betterEdges ++ [tedge] ++ rest ++ otherImports, failcount+1)
          else
--            Debug.Trace.trace ("I!")
              ( applyLink tdg tedge, edges, 0)
      else
  --      Debug.Trace.trace ("DooI" ++ show (fromxname, toxname) ++ " " ++ show (from, to) ++ " -> " ++ (show $ map (\(a,b,(_,c)) -> (a,b, dgl_type c)) unprocessedFrom) )
          ((tdg, ffxi), edges ++ [tedge], failcount+1) -- try other edge in processImportsAndMorphisms
  where
    hasCASLMorphism::DGLinkLab->Bool
    hasCASLMorphism dgl' =
      let
        caslmorph = Hets.getCASLMorphLL dgl'
      in
        not $ and
          [
              (Map.null (sort_map caslmorph))
            , (Map.null (pred_map caslmorph))
            , (Map.null (fun_map caslmorph))
          ]
    applyLink::TaggedEdgeDGraph->Graph.LEdge (Int, DGLinkLab)->(TaggedEdgeDGraph, FFXInput)
    applyLink
      tdg'
      (from',  to' , (tag', dgl')) =
      let
        fromxname = Map.findWithDefault (error "No such name!") from' nxm
        toxname = Map.findWithDefault (error "No such name!") to' nxm
        caslmorph = Hets.getCASLMorphLL dgl'
        sourcesorts =
          Map.findWithDefault
            Set.empty
            fromxname
            (xnSortsMap ffxi)
        sourcepreds =
          Map.findWithDefault
            Set.empty
            fromxname
            (xnPredsMap ffxi)
        sourceops =
          Map.findWithDefault
            Set.empty
            fromxname
            (xnOpsMap ffxi)
        targetsorts =
          Map.findWithDefault
            Set.empty
            toxname
            (xnSortsMap ffxi)
        targetpreds =
          Map.findWithDefault
            Set.empty
            toxname
            (xnPredsMap ffxi)
        targetops =
          Map.findWithDefault
            Set.empty
            toxname
            (xnOpsMap ffxi)
        newNode =
          Hets.addSignsAndHideWithMorphism
            (untagEdges tdg')
            (sortSet (msource caslmorph))
            caslmorph
            from' 
            to'
        graphEdges = Graph.labEdges tdg'
        allButThisEdge =
          filter 
            (\(_, _, (tag'', _)) -> tag'' /= tag')
            graphEdges
        savedEdges =
            filter
              (\(froms, tos, _) ->
                (froms == to') || (tos == to')
              )
              allButThisEdge
        unmodifiedEdges =
          filter
            (\(_, _, (t, _)) ->
              case
                find (\(_, _, (t', _)) -> t == t') savedEdges
              of
                Nothing -> True
                _ -> False
            )
            allButThisEdge
        dgUnmodified =
          Graph.mkGraph (Graph.labNodes tdg') unmodifiedEdges
        dgWithNewNode =
          Graph.insNode (to', newNode) $ Graph.delNode to' dgUnmodified
        dgWithNewNodeAndOldEdges =
          Graph.insEdges savedEdges dgWithNewNode
        newmorphdg = case dgl_type dgl of
          (HidingDef {}) ->
            caslmorph
              {
                  msource = getSign (untagEdges dgWithNewNodeAndOldEdges) to'
                , mtarget = getSign (untagEdges dgWithNewNodeAndOldEdges) from'
              }
          _ ->
            caslmorph
              {
                  msource = getSign (untagEdges dgWithNewNodeAndOldEdges) from'
                , mtarget = getSign (untagEdges dgWithNewNodeAndOldEdges) to'
              }
        newEdge =
          (
              from'
            , to'
            , (tag' , dgl
                {
                  dgl_morphism =
                    Hets.makeCASLGMorphism
                      newmorphdg
                }
              )
          )
        newtsorts = Set.union sourcesorts targetsorts
        newtpreds = Set.union sourcepreds targetpreds
        newtops = Set.union sourceops targetops
        newffxi = 
          ffxi
            {
                xnSortsMap = Map.insert toxname newtsorts (xnSortsMap ffxi)
              , xnPredsMap = Map.insert toxname newtpreds (xnPredsMap ffxi)
              , xnOpsMap = Map.insert toxname newtops (xnOpsMap ffxi)
            }
      in
        (Graph.insEdge newEdge dgWithNewNodeAndOldEdges, newffxi)

getSign::DGraph->Graph.Node->CASLSign
getSign dgs sn =
  let
    snode =
      fromMaybe
        (error ("No such node in Graph : \"" ++ show sn ++ "\""))
        (Graph.lab dgs sn)
  in
    Hets.getJustCASLSign $ Hets.getCASLSign (dgn_sign snode)

getCatalogueInformation::HXT.XmlTrees->(Map.Map String String)
getCatalogueInformation t =
  let
    catalogue = applyXmlFilter (getChildren .> isTag "catalogue") t
    locs = applyXmlFilter (getChildren .> isTag "loc") catalogue
    list = foldl (\l loc ->
      l ++ [ (xshow $ applyXmlFilter (getValue "theory") [loc],
              xshow $ applyXmlFilter (getValue "omdoc") [loc])
           ]
      ) [] locs
  in
    Map.fromList list
              

-- | theory name, theory source (local)
data TheoryImport = TI (String, String)

instance Show TheoryImport where
  show (TI (tn, ts)) = ("Import of \"" ++ tn ++ "\" from \"" ++ ts ++ "\".")

-- | source name, source (absolute)
--data Source a = S { nameAndURI::(String, String), sContent::a } 
data Source a = S (String, String) a

instance Show (Source a) where
  show (S (sn, sf) _) = ("Source \"" ++ sn ++ "\" File : \"" ++ sf ++ "\".");

type ImportGraph a = CLGraph.Gr (Source a) TheoryImport 


maybeGetXml::String->IO (Maybe HXT.XmlTrees)
maybeGetXml source =
  do
    xml <- HXT.run' $
      HXT.parseDocument
        [
            (HXT.a_source, source)
          , (HXT.a_issue_errors, HXT.v_0)
          , (HXT.a_check_namespaces, HXT.v_1)
          , (HXT.a_validate, HXT.v_0)
        ]
        HXT.emptyRoot
    return
      (let
        status = (read $ HXT.xshow $ getValue "status" (head xml))::Int
        result = if status < HXT.c_err then (Just xml) else Nothing
      in
        result)
                                
maybeFindXml::String->[String]->IO (Maybe HXT.XmlTrees)
maybeFindXml source includes =
  let
    muri = URI.parseURIReference source
    uri = fromMaybe (error "cannot parse URIReference") muri
    isFile = (length (URI.uriScheme $ uri)) == 0
    filePath = URI.uriPath uri
    isAbsolute = (isFile && ( (head filePath) == '/')) || (URI.isAbsoluteURI source)
    possibilities = source:(if not isAbsolute then map (++"/"++source) includes else [])
  in
    do
      case muri of
        Nothing -> return Nothing
        _ -> firstSuccess (map maybeGetXml possibilities)
  where
    firstSuccess::(Monad m)=>[(m (Maybe a))]->(m (Maybe a))
    firstSuccess [] = return Nothing
    firstSuccess (l:r) =
      do
        res <- l
        case res of
          Nothing -> firstSuccess r
          _ -> return res
                                  


getImportedTheories::HXT.XmlTrees->Map.Map String String
getImportedTheories xml =
  let
    omdoc = applyXmlFilter (getChildren .> isTag "omdoc") xml
    catmap = getCatalogueInformation omdoc
    timports = map (\n -> xshow [n]) $
      applyXmlFilter
        (getChildren .> isTag "theory" .>
                getChildren .> isTag "imports" .> getValue "from")
        omdoc
    tincs = map (\n -> xshow [n]) $
      applyXmlFilter
        (getChildren .>
          (isTag "theory-inclusion" +++ isTag "axiom-inclusion") .>
          getValue "from"
        )
        omdoc
    externalImports = foldl (\eI i ->
      let
        muri = URI.parseURIReference i
        uri = fromMaybe (error "cannot parse URIReference") muri
        path = URI.uriPath uri
        fragment = drop 1 $ URI.uriFragment uri
      in
        if ((length path) > 0) && ((length fragment) > 0)
          then
            Map.insert fragment path eI
          else
            eI
      ) Map.empty (timports ++ tincs)
  in
    Map.union catmap externalImports
        
                                        
makeImportGraphFullXml::GlobalOptions->String->(IO (ImportGraph HXT.XmlTrees))
makeImportGraphFullXml go source =
  do
    curdirs <- System.Directory.getCurrentDirectory
    -- trick the uri parser into faking a document to make a relative path later
    mcduri <- return $ URI.parseURIReference ("file://"++curdirs++"/a")
    alibdir <- return $ case mcduri of
      Nothing -> (libdir (hetsOpts go))
      (Just cduri) -> relativeSource cduri (libdir (hetsOpts go))
    putIfVerbose (hetsOpts go) 0 ("Loading " ++ source ++ "...") 
    mdoc <- maybeFindXml source [alibdir]
    case mdoc of
      Nothing -> ioError $ userError ("Unable to find \"" ++ source ++ "\"")
      (Just doc) ->
        (let
          omdoc = applyXmlFilter (getChildren .> isTag "omdoc") doc
          omdocid = xshow $ applyXmlFilter (getQualValue "xml" "id") omdoc
          mturi =
            URI.parseURIReference
              $
              xshow
                $
                getValue "transfer-URI" (head doc)
          turi = fromMaybe (error "Cannot parse URIReference...") mturi
          muriwithoutdoc =
            URI.parseURIReference
              $
              (reverse $ dropWhile (/='/') $ reverse (show turi))
          uriwithoutdoc =
            fromMaybe
              (error "Cannot create path to document...")
              muriwithoutdoc
          docmap = getImportedTheories doc
          rdocmap = Map.toList docmap -- Map.toList $ Map.map (\s -> relativeSource turi s) docmap
          initialgraph = Graph.mkGraph [(1, S (omdocid, (show turi)) omdoc)] []
        in
          foldl
            (\gio (itname, ituri)  ->
              gio >>= \g -> buildGraph g 1 uriwithoutdoc (TI (itname, ituri)) alibdir
            ) (return initialgraph) rdocmap
        )
  where
  buildGraph::
    ImportGraph HXT.XmlTrees
    ->Graph.Node
    ->URI.URI
    ->TheoryImport
    ->String
    ->IO (ImportGraph HXT.XmlTrees)
  buildGraph ig n frompath ti@(TI (theoname, theouri)) alibdir =
    let
      includes = [alibdir, (show frompath)]
      possources =
        theouri:(
          map
            (\s -> s ++ (if (last s)=='/' then "" else "/") ++ theouri)
            includes
          )
      mimportsource =
        find
          (\(_, (S (_, suri) _)) -> any (\s -> suri == s) possources)
          (Graph.labNodes ig)
    in
    do
      case mimportsource of
        (Just (inum, (S (isn,_) _))) ->
            do
              putIfVerbose
                (hetsOpts go)
                0
                ("Loading " ++ theoname ++ " from "
                  ++ theouri ++ " (cached)..." 
                )
              return 
                (if inum == n then
                   debugGO
                    go
                    "mIGFXbG"
                    ("Back-reference in " ++ isn ++ " to " ++ theoname)
                    ig
                 else
                   (Graph.insEdge (n, inum, ti) ig)
                )
        Nothing ->
          do
            putIfVerbose
              (hetsOpts go)
              0
              ("Loading " ++ theoname ++ " from " ++ theouri ++ "...")
            mdocR <- maybeFindXml theouri includes
            mdoc <- case mdocR of
              Nothing ->
                do
                  putIfVerbose
                    (hetsOpts go)
                    0
                    ("error at loading from " ++ (show includes))
                  ioError
                    $
                    userError
                      ("Unable to find \"" ++ theouri
                        ++ "\" (looked in " ++ (show includes) ++ ")"
                      )
              _ -> return mdocR
            (newgraph, nn, importimports, newbase) <-
              return $
                (
                  let
                    doc =
                      fromMaybe
                        (error
                          ("Unable to import \""++ theoname 
                            ++ "\"from \"" ++ theouri ++ "\"")
                        )
                        mdoc
                    omdoc = applyXmlFilter (getChildren .> isTag "omdoc") doc
                    omdocid =
                      xshow
                        $
                        applyXmlFilter (getQualValue "xml" "id") omdoc
                    imturi =
                      URI.parseURIReference
                        $
                        xshow $ getValue "transfer-URI" (head doc)
                    ituri = fromMaybe (error "Cannot parse URIReference...") imturi
                    miuriwithoutdoc =
                      URI.parseURIReference
                        $
                        (reverse $ dropWhile (/='/') $ reverse (show ituri))
                    iuriwithoutdoc =
                      fromMaybe
                        (error "Cannot create path to document...")
                        miuriwithoutdoc
                    iimports = getImportedTheories doc
                    irimports = Map.toList iimports
                    newnodenum = (Graph.noNodes ig) + 1
                    newsource = S (omdocid, (show ituri)) omdoc
                    newgraph =
                      Graph.insEdge
                        (n, newnodenum, ti)
                        $
                        Graph.insNode (newnodenum, newsource) ig
                  in
                    (newgraph, newnodenum, irimports, iuriwithoutdoc)
                )
            foldl
              (\nigio (itheoname, itheouri) ->
                nigio >>= \nig ->
                  buildGraph nig nn newbase (TI (itheoname, itheouri)) alibdir
              )
              (return newgraph)
              importimports
  relativeSource::URI.URI->String->String
  relativeSource uri s =
    let
      msuri = URI.parseURIReference s
      suri = fromMaybe (error "Cannot parse URIReference") msuri
      mreluri = URI.relativeTo suri uri
      reluri = fromMaybe (error "Cannot create relative URI...") mreluri
    in
      case msuri of
        Nothing -> s
        _ -> case mreluri of
          Nothing -> s
          _ -> URI.uriToString id reluri ""
                                                
                                                
        
-- if there is a cycle in the imports this will fail because the algorithm
-- processes only omdoc's that do import from already processed omdoc's or do
-- not import at all.
processImportGraphXN::
  GlobalOptions -- ^ global options for debugging
  ->(ImportGraph HXT.XmlTrees) -- ^ initial import graph
  ->(ImportGraph (HXT.XmlTrees, Maybe (DGraph, FFXInput))) -- ^ import graph with created DGraphs
processImportGraphXN go ig =
  let
    -- create hybrid graph containing already processed DGs (none at first)
    hybrid = Graph.mkGraph
            (map (\(n, S a b) -> (n, S a (b, Nothing))) $ Graph.labNodes ig)
            (Graph.labEdges ig) :: (ImportGraph (HXT.XmlTrees, (Maybe (DGraph, FFXInput))))
    -- create all DG's
    processed = process hybrid
  in
    processed
  where
    -- transform one node's omdoc-content to a DGraph and proceed until
    -- no more transformations are possible
    process ::
      (ImportGraph (HXT.XmlTrees, (Maybe (DGraph, FFXInput)))) ->
      (ImportGraph (HXT.XmlTrees, (Maybe (DGraph, FFXInput))))
    process igxmd =
      let
        -- which nodes have no DGraph ?
        unprocessed = filter (\(_, S _ (_, mdg)) ->
          case mdg of
            Nothing -> True
            _ -> False
          ) $ Graph.labNodes igxmd
        -- targets are nodes that import only from processed nodes
        -- or do not import at all
        targets = filter (\(nodenum, _) ->
          let
            -- get the outgoing edges (imports) for this node
            imports' = Graph.out ig nodenum
            -- for all these edges, check whether it points
            -- to an unprocessed node
            unprocessedimports = filter (\(_,from,_) ->
              -- but do not count a reference back to current node...
              if null (filter (\(n,_) -> (n/=nodenum) && (from == n)) unprocessed)
                then
                  False
                else
                  True
                ) imports'
          in
            -- the filter is just to check, if there
            -- is something unprocessed 'in the way'
            null unprocessedimports ) unprocessed
      in
        -- okay, have any nodes survived the filter ?
        if null targets
          then
            -- no targets left
            igxmd
          else
            -- okay, process a target
            let
              -- does not really matter what target to choose...
              changednode = head targets
              -- perform conversion
              --(dg, name) = omdocToDevGraph $
              --      (\(_, S _ (omdoc, _)) -> omdoc) changednode
              changednodenum =
                (\(nodenum, _) -> nodenum) changednode
              (skeldg, nxm, ffxi, axtheoryset) = importGraphToDGraphXN go igxmd changednodenum
{-              dg = applyGlobalImportsAndHiding
                $ applyLocalImportsAndHiding
                  $ fixDGMorphisms ffxi skeldg -}
              (dg, newffxi) = processImportsAndMorphisms skeldg nxm ffxi
              sensmap =
                debugEnv
                  "processImportGraph"
                  (show (xnSortsMap ffxi) ++ " -> " ++ show (xnSortsMap newffxi))
                  $
                  sensXNWONFromXml go newffxi axtheoryset
              mdg = fixMorphisms $ mergeSentences nxm sensmap dg
              -- name = (\(_, (S (nname,_) _)) -> nname) changednode
              -- create the altered node
              newnode = (\(nodenum, S a (omdoc,_)) ->
                (nodenum, S a (omdoc, Just (mdg, newffxi)))) changednode
              -- fetch all other nodes
              othernodes = filter
                (\(n,_) -> n /= changednodenum) $
                  Graph.labNodes igxmd
            in
              -- start the next round with the new graph
              process $ Graph.mkGraph
                (newnode:othernodes)
                (Graph.labEdges igxmd)

{- |
  After merging all sentences for a target-node, the morphisms still
  point to the old signature. This function updates the target-
  signatures of all morphisms.
-}
fixMorphisms::DGraph->DGraph
fixMorphisms dg =
  let
    labnodes = Graph.labNodes dg
    labedges = Graph.labEdges dg
    newedges =
      foldl
        (\ne (from, to, dgl) ->
          let
            caslmorph = Hets.getCASLMorphLL dgl
            tonode =
              fromMaybe
                (error "!")
                $
                Graph.lab dg to
            nodesign =
              Hets.getJustCASLSign $ Hets.getCASLSign (dgn_sign tonode)
            newmorph =
              caslmorph
                {
                  mtarget = nodesign
                }
          in
            ne ++
              [
                (
                  from
                  , to
                  , dgl { dgl_morphism = Hets.makeCASLGMorphism newmorph }
                )
              ]
        )
        []
        labedges
  in
    Graph.mkGraph labnodes newedges

{- |
  insert sentences from xml into the nodes (after all sorts are known).
-}
mergeSentences::
  Map.Map Graph.Node XmlName ->
  Map.Map XmlName (Set.Set (XmlNamed Hets.SentenceWO))->
  DGraph->
  DGraph
mergeSentences
  nodexnamemap
  sensmap
  dg
  =
  let
    labnodes = Graph.labNodes dg
    labedges = Graph.labEdges dg
    newnodes =
      foldl
        (\nn (nodenum, dgn)->
          case
            Map.lookup nodenum nodexnamemap
          of
            Nothing -> error "!"
            (Just nodexmlname) ->
              let
                sensset = Map.findWithDefault Set.empty nodexmlname sensmap
                caslsign =
                  Hets.getJustCASLSign $ Hets.getCASLSign (dgn_sign dgn) 
                newdgn =
                  dgn
                    {
                      dgn_theory =
                        G_theory
                          CASL
                          caslsign
                          (Prover.toThSens
                            $
                            map
                              xnWOaToa
                              (Set.toList sensset)
                          )
                    }
              in
               nn ++ [(nodenum, newdgn)]
        )
        []
        labnodes
  in
    Graph.mkGraph newnodes labedges
                                                                
hybridGToDGraphG::
  GlobalOptions
  ->(ImportGraph (HXT.XmlTrees, Maybe (DGraph, FFXInput)))
  ->(ImportGraph DGraph)
hybridGToDGraphG _ ig =
  Graph.mkGraph
    (map
      (\(n, (S a (_,mdg))) ->
        let
          dg =
            case mdg of
              Nothing ->
                error
                  "Cannot convert hybrid with unresolved DGraphs..."
              (Just (dg', _)) -> dg'
        in
          (n, (S a dg))
      )
      $
      Graph.labNodes ig
    )
    (Graph.labEdges ig)

dGraphGToLibEnvOMDocId::
  GlobalOptions
  ->(ImportGraph DGraph)
  ->(ASL.LIB_NAME, DGraph, LibEnv)
dGraphGToLibEnvOMDocId _ ig =
  let
    nodes = map (\(_,n) -> n) $ Graph.labNodes ig
    firstnode =
      case nodes of
        [] -> error "empty graph..."
        l -> head l
    firstsrc = (\(S (sn,_) _) -> sn) firstnode
    firstdg = (\(S _ dg) -> dg) firstnode
    lenv =
      Map.fromList
        $
        map
          (\(S (sn, _) dg) ->
            (
                (ASL.Lib_id (ASL.Indirect_link sn Id.nullRange)) 
              , emptyGlobalContext { devGraph = dg }
            )
          )
          nodes
  in
    (ASL.Lib_id (ASL.Indirect_link firstsrc Id.nullRange), firstdg, lenv)
                
-- | create an origin from string.
stringToOrigin::String->Static.DevGraph.DGOrigin
stringToOrigin s
  | (s == "DGBasic") = DGBasic 
  | (s == "DGExtension") = DGExtension
  | (s == "DGTranslation") = DGTranslation 
  | (s == "DGUnion") = DGUnion
  | (s == "DGHiding") = DGHiding 
  | (s == "DGRevealing") = DGRevealing 
  | (s == "DGRevealTranslation") = DGRevealTranslation 
  | (s == "DGFree") = DGFree
  | (s == "DGCofree") = DGCofree
  | (s == "DGLocal") = DGLocal
  | (s == "DGClosed") = DGClosed
  | (s == "DGClosedLenv") = DGClosedLenv
  | (s == "DGLogicQual") = DGLogicQual
  | (s == "DGLogicQualLenv") = DGLogicQualLenv
  | (s == "DGData") = DGData
  | (s == "DGFormalParams") = DGFormalParams
  | (s == "DGImports") = DGImports
  | (s == "DGFitSpec") = DGFitSpec
  | (s == "DGProof") = DGProof
  | otherwise =
    if isPrefix "DGSpecInst " s
      then
        DGSpecInst (Hets.stringToSimpleId (drop (length "DGSpecInst ") s))
      else
        if isPrefix "DGView " s
          then
            DGView (Hets.stringToSimpleId (drop (length "DGView ") s))
          else
            if isPrefix "DGFitView " s
              then
                DGFitView (Hets.stringToSimpleId (drop (length "DGFitView ") s))
              else
                if isPrefix "DGFitViewImp " s
                  then
                    DGFitViewImp
                      (Hets.stringToSimpleId
                        (drop (length "DGFitViewImp ") s)
                      )
                  else
                    if isPrefix "DGFitViewA " s
                      then
                        DGFitViewA
                          (Hets.stringToSimpleId
                            (drop (length "DGFitViewA ") s)
                          )
                      else
                        if isPrefix "DGFitViewAImp " s
                          then
                            DGFitViewAImp
                              (Hets.stringToSimpleId
                                (drop (length "DGFitViewAImp ") s)
                              )
                          --else error ("No such origin \"" ++ s ++ "\"")
                          else
                            DGBasic


createQuasiMappedLists::Eq a=>[(a,a)]->[(a,[a])]
createQuasiMappedLists = foldl (\i x -> insert x i) []
  where 
  insert::(Eq a, Eq b)=>(a,b)->[(a,[b])]->[(a,[b])]
  insert (a,b) [] = [(a,[b])]
  insert (a,b) ((a' ,l):r) =
    if a == a'
      then
        (a' , l++[b]):r
      else
        (a', l) : insert (a,b) r
        
isTrueAtom::(FORMULA ())->Bool
isTrueAtom (True_atom _) = True
isTrueAtom _ = False

-- X M L -> FORMULA

unwrapFormulasXNWON::FFXInput->AnnXMLN->[(XmlNamed Hets.SentenceWO)]
unwrapFormulasXNWON ffxi anxml =
  let
    axioms =
      applyXmlFilter (getChildren .> isTag "axiom") (axXml anxml)
  in
    foldl
      (\unwrapped axxml ->
        let
          ansen = unwrapFormulaXNWON ffxi (AXML (axAnn anxml) [axxml])
          ansenname = Ann.senName ansen
          anpress = getPresentationString ansenname (axXml anxml)
          anname =
            case anpress of
              [] ->
                debugGO
                  (ffxiGO ffxi)
                  "uFXNWON"
                  ("F-Name: " ++ ansenname)
                  ansenname
              _ ->
                debugGO
                  (ffxiGO ffxi)
                  "uFXNWON"
                  ("F-Pres: " ++ anpress)
                  anpress
        in
          (
            unwrapped
            ++ [
                XmlNamed
                  (Hets.mkWON (ansen { Ann.senName = anname }) (axAnn anxml))
                  ansenname
               ]
          )
      )
      []
      axioms

unwrapFormulaXNWON::FFXInput->AnnXMLN->(Ann.Named CASLFORMULA)
unwrapFormulaXNWON ffxi anxml =
  let
    axname =
      xshow
        $
        applyXmlFilter
          (getQualValue axiomNameXMLNS axiomNameXMLAttr)
          (axXml anxml)
    formtree =
      applyXmlFilter
        (getChildren .> isTag "FMP" .> getChildren
          .> isTag "OMOBJ" .> getChildren)
        (axXml anxml)
  in
    Ann.NamedSen
      (axname)
      True
      False
      (formulaFromXmlXN ffxi (AXML (axAnn anxml) formtree))

-- create FFXInput and a set of annotated theory-fragments.
preprocessXml::
  GlobalOptions
  ->Map.Map
      XmlName
      FFXInput
  ->HXT.XmlTrees
  ->(FFXInput, Set.Set AnnXMLN)
preprocessXml go cdmap t =
  let
    axtheoryset =
      buildAXTheorySet
        (debugGO go "pX" "at buildAXTheorySet" t)
    xntheoryset =
      nodeNamesXNFromXml
        (debugGO go "pX" "at nodeNamedXNFromXml" axtheoryset)
    xnsortsmap =
      sortsXNWONFromXml
        xntheoryset
        (debugGO go "pX" "at sortsXNWONFromXml" axtheoryset)
    xnsorts =
      mapSetToSet (debugGO go "pX" "at mapToSet" xnsortsmap)
    xnrelsmap =
      relsXNWONFromXml
        xntheoryset
        xnsorts
        (debugGO go "pX" "at relsXNWONFromXML" axtheoryset)
    xnpredsmap =
      mapListToMapSet
        $
        predsXNWONFromXml
          cdmap
          xntheoryset
          xnsorts
          (debugGO go "pX" "at predsXNWONFromXml" axtheoryset)
    xnopsmap =
      mapListToMapSet
        $
        opsXNWONFromXml
          cdmap
          xntheoryset
          xnsorts
          (debugGO go "pX" "at opsXNWONFromXml" axtheoryset)
  in
    (emptyFFXInput
      {
          ffxiGO = go
        , xnTheorySet = xntheoryset
        , xnSortsMap = xnsortsmap
        , xnRelsMap = xnrelsmap
        , xnPredsMap = xnpredsmap
        , xnOpsMap = xnopsmap 
      }
      , axtheoryset
    )

data FFXInput = FFXInput {
         ffxiGO :: GlobalOptions
        ,xnTheorySet :: TheoryXNSet -- set of theorys (xmlnames + origin in graph)
        ,xnSortsMap :: Map.Map XmlName (Set.Set XmlNamedWONSORT) -- theory -> sorts mapping
        ,xnRelsMap :: Map.Map XmlName (Rel.Rel XmlNamedWONSORT) -- theory -> rels
        ,xnPredsMap :: Map.Map XmlName (Set.Set (XmlNamedWONId, PredTypeXNWON)) -- theory -> preds
        ,xnOpsMap :: Map.Map XmlName (Set.Set (XmlNamedWONId, OpTypeXNWON)) -- theory -> ops
        }
  deriving Show
        
        
emptyFFXInput::FFXInput
emptyFFXInput =
        FFXInput
                emptyGlobalOptions
                Set.empty
                Map.empty
                Map.empty
                Map.empty
                Map.empty

stripFragment::String->String
stripFragment s =
  let
    (file, theo) = span (/='#') s
  in
    case theo of
      [] -> file
      _ -> drop 1 theo
                
formulaFromXmlXN::FFXInput->AnnXMLN->FORMULA ()
formulaFromXmlXN ffxi anxml =
  if (applyXmlFilter (isTag "OMBIND") (axXml anxml)) /= [] then -- it's a quantifier...
    let
      quantTree = singleitem 1 (applyXmlFilter (isTag "OMBIND") (axXml anxml))
      quant =
        quantFromName $ xshow $
          applyXmlFilter
            (getChildren .> isTag "OMS" .> withValue "cd" (\s -> (stripFragment s) == caslS) .>
              getValue "name")
            quantTree
      -- first element is the quantification-OMS
      formula =
        drop
          1
          ((applyXmlFilter
            (getChildren .> (isTag "OMA" +++ isTag "OMATTR"
              +++ isTag "OMBIND" +++ isTag "OMS"))
            quantTree)::[HXT.XmlTree]
          ) 
      vardeclS =
        getVarDecls
          (applyXmlFilter
            (getChildren .> isTag "OMBVAR")
            quantTree
          )
      vardeclS2 = createQuasiMappedLists vardeclS
    in
      Quantification
        quant
        (map
          (\(s, vl) ->
            Var_decl
              (map Hets.stringToSimpleId vl)
              (case findByNameAndOrigin
                      (stripFragment s)
                      (axAnn anxml)
                      (mapSetToSet $ xnSortsMap ffxi) of
                 Nothing -> error ("No Sort for " ++ s)
                 (Just x) -> xnWOaToa x
              )
              --(Hets.stringToId s)
              Id.nullRange
          )
          vardeclS2
        )
        (formulaFromXmlXN
          ffxi
          (AXML (axAnn anxml) formula)
        )
        Id.nullRange
  else if (applyXmlFilter (isTag "OMA") (axXml anxml)) /= [] then -- the case begins...
    let
      formTree = applyXmlFilter (isTag "OMA") (axXml anxml)
      applySymXml =
        singleitem 1 (applyXmlFilter (getChildren .> isTag "OMS") formTree)
      applySym = xshow $ applyXmlFilter (getValue "name") applySymXml
      --applySymCD = xshow $ applyXmlFilter (getValue "cd") applySymXml
    in
      let
        formulas =
          map
            (\n -> formulaFromXmlXN ffxi (AXML (axAnn anxml) [n]))
            (
              (applyXmlFilter
                (getChildren .>
                  (isTag "OMA" +++ isTag "OMATTR" +++ isTag "OMBIND")
                )
                formTree
              )::[HXT.XmlTree]
            )
        terms =
          map
            (\n -> termFromXmlXN ffxi (AXML (axAnn anxml) [n]))
            (tail
              (
                (applyXmlFilter
                  (getChildren .>
                    (isTag "OMV" +++ isTag "OMATTR" +++ isTag "OMA"
                      +++ isTag "OMS")
                  )
                  formTree
                )::[HXT.XmlTree]
              )
            )
      in
        -- 'case applySym' does not work if case-strings are non fixed
        -- (above definition is not fixed enough...) 
        --case applySym of
        if applySym == caslConjunctionS then
          Conjunction formulas Id.nullRange
          else
            if applySym == caslDisjunctionS then
              Disjunction formulas Id.nullRange
              else
                if applySym `elem` [caslImplicationS, caslImplication2S] then
                  let
                    boolF =
                      formulaFromXmlXN
                        ffxi
                        (AXML
                          (axAnn anxml)
                          (applyXmlFilter
                            (processChildren (isTag "OMS") .> getChild 2)
                            formTree)
                          ) 
                  in
                    if (length formulas) < 2
                      then
                        Debug.Trace.trace
                          ("Impossible to create implication...")
                          (False_atom Id.nullRange)
                      else
                        Implication
                          (formulas!!0)
                          (formulas!!1)
                          (isTrueAtom(boolF))
                          Id.nullRange
                  else
                    if applySym `elem` [caslEquivalenceS, caslEquivalence2S]
                      then
                        if (length formulas) < 2
                          then
                            Debug.Trace.trace
                              ("Impossible to create equivalence...")
                              (False_atom Id.nullRange)
                          else
                            Equivalence
                              (formulas!!0)
                              (formulas!!1)
                              Id.nullRange
                      else
                        if applySym == caslNegationS
                          then
                            if formulas == []
                              then
                                Debug.Trace.trace
                                  ("Impossible to create negation...")
                                  (False_atom Id.nullRange)
                              else
                                Negation
                                  (formulas!!0)
                                  Id.nullRange
                          else
                            if applySym == caslPredicationS
                              then
                                let
                                   --predxml = applyXmlFilter (processChildren (isTag "OMS" +++ isTag "OMATTR") .> getChild 2) (axXml anxml)
                                  predxml =
                                    applyXmlFilter
                                      (processChildren
                                        (isTag "OMS" +++ isTag "OMATTR") .>
                                          getChild 2
                                      )
                                      formTree
                                  pred' =
                                    (\x ->
                                      if (contains (show x) "predication")
                                        then
                                          debugGO
                                            (ffxiGO ffxi)
                                            "fFXXNm2"
                                            ("predication created! from : "
                                              ++ (xshow predxml)) x
                                        else
                                          x
                                    ) $
                                      (\x ->
                                        debugGO
                                          (ffxiGO ffxi)
                                          "fFXXNm"
                                          ("made pred : " ++ show x)
                                          x
                                      ) $
                                        predicationFromXmlXN
                                          ffxi
                                          (AXML (axAnn anxml) predxml)
                                  --termxml = drop 2 $ (applyXmlFilter (getChildren .> (isTag "OMATTR" +++ isTag "OMA" +++ isTag "OMS")) (axXml anxml))
                                  termxml =
                                    drop 2 $
                                      (applyXmlFilter
                                        (getChildren .>
                                          (isTag "OMATTR" +++ isTag "OMA"
                                            +++ isTag "OMS")
                                        )
                                        formTree
                                      )
                                  predterms =
                                    map
                                      (\tx ->
                                        termFromXmlXN
                                          ffxi
                                          (debugGO
                                            (ffxiGO ffxi)
                                            "fFXXN"
                                            ("will create term(1) from : "
                                              ++ (take 200 $ xshow [tx])
                                            )
                                            (AXML (axAnn anxml) [tx])
                                          )
                                      )
                                      termxml
                                in
                                  if predxml == []
                                    then
                                      Debug.Trace.trace
                                        ("Impossible to create predication...")
                                          (False_atom Id.nullRange)
                                    else
                                      Predication
                                        pred'
                                        predterms
                                        Id.nullRange 
                              else
                                if applySym == caslDefinednessS
                                  then
                                    Definedness
                                      (termFromXmlXN
                                        ffxi
                                        (debugGO
                                          (ffxiGO ffxi)
                                          "fXXN"
                                          ((++) "About to create Definedness from "
                                            $ take 300 $ xshow $ axXml anxml
                                          )
                                          (AXML
                                            (axAnn anxml)
                                            (drop 1 $
                                              (applyXmlFilter
                                                (getChildren .>
                                                  (isTag "OMV" +++ isTag "OMATTR"
                                                    +++ isTag "OMA" +++ isTag "OMS" )
                                                )
                                                (axXml anxml)
                                              )
                                            )
                                          )
                                        )
                                      )
                                      Id.nullRange
                                  else
                                    if applySym == caslExistl_equationS
                                      then
                                        if (length terms) < 2
                                          then
                                            Debug.Trace.trace
                                              ("Impossible to create existl_equation...")
                                              (False_atom Id.nullRange)
                                          else
                                            Existl_equation
                                              (terms!!0)
                                              (terms!!1)
                                              Id.nullRange
                                      else
                                        if applySym == caslStrong_equationS
                                          then
                                            if (length terms) < 2
                                              then
                                                Debug.Trace.trace
                                                  ("Impossible to create strong_equation... ("
                                                    ++ (xshow formTree) ++ ")"
                                                  )
                                                  (False_atom Id.nullRange)
                                              else
                                                Strong_equation
                                                  ((\x ->
                                                    if (contains (show x) "predication")
                                                      then
                                                        debugGO
                                                          (ffxiGO ffxi)
                                                          "fFXXNse"
                                                          ("predication created! from : (0)")
                                                          x
                                                      else
                                                        x
                                                    ) (terms!!0)
                                                  )
                                                  ((\x ->
                                                    if (contains (show x) "predication")
                                                      then
                                                        debugGO
                                                          (ffxiGO ffxi)
                                                          "fFXXNse"
                                                          ("predication created! from : (1)")
                                                          x
                                                      else
                                                        x
                                                      ) (terms!!1)
                                                  )
                                                  Id.nullRange
                                          else
                                            if applySym == caslMembershipS
                                              then
                                                let
                                                  sortxml =
                                                    lastorempty
                                                      (applyXmlFilter
                                                        (getChildren .> isTag "OMS")
                                                        formTree
                                                      )
                                                  sort = xshow $ applyXmlFilter (getValue "name") sortxml
                                                  sortcd =
                                                    stripFragment
                                                      $
                                                      xshow
                                                        $
                                                        applyXmlFilter
                                                          (getValue "cd")
                                                          sortxml
                                                  theosorts =
                                                    Map.findWithDefault
                                                      Set.empty
                                                      sortcd
                                                      (xnSortsMap ffxi) 
                                                  sortxn =
                                                    case findByName sort theosorts of
                                                      Nothing ->
                                                        error
                                                          ("Sort not found in theory!"
                                                            ++ "(" ++ sort ++ ", "
                                                              ++ (show theosorts) ++ ")" 
                                                          )
                                                      (Just x) -> x
                                                in
                                                  if terms == []
                                                    then
                                                      Debug.Trace.trace
                                                        ("Impossible to create Membership...")
                                                        (False_atom Id.nullRange)
                                                    else
                                                      Membership
                                                        (head terms)
                                                        (debugGO
                                                           (ffxiGO ffxi)
                                                           "fFXXN"
                                                           ("Making sort for membership "
                                                            ++ (show $ xnWOaToa sortxn)
                                                            ++ " from " ++ sort
                                                           )
                                                           (xnWOaToa sortxn)
                                                        )
                                                        Id.nullRange
                                              else
                                                if applySym == caslSort_gen_axS
                                                  then
                                                    let
                                                      freeType =
                                                        if (xshow $
                                                          applyXmlFilter
                                                            (getValue "name")
                                                            [(applyXmlFilter
                                                              (getChildren .> isTag "OMS")
                                                              formTree)!!1
                                                            ]
                                                            ) == caslSymbolAtomFalseS
                                                          then
                                                            False
                                                          else
                                                            True
                                                      constraintsx =
                                                        applyXmlFilter
                                                          (
                                                          --getChildren .> isTag "OMBVAR" .> -- removed (see generation)
                                                          getChildren .> isTag "OMBIND"
                                                          )
                                                          formTree
                                                      constraints =
                                                        xmlToConstraintsXN
                                                          ffxi
                                                          (AXML (axAnn anxml) constraintsx)
                                                    in
                                                      Sort_gen_ax constraints freeType
                                                  else
                                                    if applySym /= []
                                                      then
                                                        Debug.Trace.trace
                                                          ("No matching casl-application found! Trying to find predicate...") $ let
                         predterms =
                          map (\n -> termFromXmlXN ffxi (AXML (axAnn anxml) [n])) $ ((applyXmlFilter (getChildren .> (isTag "OMATTR" +++ isTag "OMA")) (axXml anxml))::[HXT.XmlTree])
                         possibilities = findAllByNameWithAnd id fst applySym (mapSetToSet (xnPredsMap ffxi))
                         withThisOrigin = filter (\i -> (xnWOaToO $ fst i) == (axAnn anxml)) possibilities
                      in
                        case (case withThisOrigin of [] -> possibilities; _ -> withThisOrigin) of
                          (i:_) ->
                            Predication (Qual_pred_name (xnWOaToa (fst i)) (Hets.cv_PredTypeToPred_type $ predTypeXNWONToPredType (snd i)) Id.nullRange) predterms Id.nullRange
                          [] ->
                            error ("Could not find predicate for \"" ++ applySym ++ "\"")
                                                      else
                                                        error ("Expected a casl application symbol, but \"" ++ applySym ++ "\" was found!")
  else if (applyXmlFilter (isTag "OMS") (axXml anxml)) /= []
    then
      let
        trueOrFalse =
          xshow $
            singleitem
              1
              (applyXmlFilter
                (isTag "OMS" .> withValue "cd" (\s -> (stripFragment s) == caslS) .>
                  getValue "name"
                )
                (axXml anxml)
              )
      in
        if trueOrFalse == caslSymbolAtomTrueS
          then
            True_atom Id.nullRange
          else
            if trueOrFalse == caslSymbolAtomFalseS
              then
                False_atom Id.nullRange
              else
                Debug.Trace.trace
                  (caslSymbolAtomTrueS ++ " or "
                    ++ caslSymbolAtomFalseS ++ " expected, but \""
                    ++ trueOrFalse ++ "\" found!"
                  )
                  (False_atom Id.nullRange)
  else
    error ("Impossible to create formula from \"" ++ xshow (axXml anxml)++ "\"") 


xmlToConstraintsXN::FFXInput->AnnXMLN->[ABC.Constraint]
xmlToConstraintsXN ffxi anxml =
  map
    (\n ->
      xmlToConstraintXN
        ffxi
        (AXML (axAnn anxml) [n])
    )
    ((applyXmlFilter (isTag "OMBIND") (axXml anxml))::[HXT.XmlTree])
        

xmlToConstraintXN::FFXInput->AnnXMLN->ABC.Constraint
xmlToConstraintXN ffxi anxml =
  let
    sortsx =
      applyXmlFilter
        (getChildren .> isTag "OMS" .> getValue "name")
        (axXml anxml)
    newsort = Hets.stringToId $ xshow $ [sortsx!!0]
    origsort = Hets.stringToId $ xshow $ [sortsx!!0]
    indiopsx =
      applyXmlFilter
        (getChildren .> isTag "OMBVAR" .> getChildren .> isTag "OMATTR")
        (axXml anxml)
    conslist =
      foldl
        (\cl cx ->
          let
            indices =
              xshow
                $
                applyXmlFilter
                  (getChildren .> isTag "OMATP" 
                    .> getChildren .> isTag "OMSTR" .> getChildren
                  )
                  [cx]
            op =
              operatorFromXmlXN
                ffxi
                $
                (\n -> AXML (axAnn anxml) n)
                  $
                  applyXmlFilter
                    (getChildren .> (isTag "OMBIND" +++ isTag "OMS"))
                    [cx]
            il =
              makeIndexList indices
          in
            cl ++ [(op, il)]
        )
        ([]::[(OP_SYMB,[Int])])
        (indiopsx::[HXT.XmlTree])
  in
    ABC.Constraint newsort conslist origsort
          
                
-- An IndexList is constructed from a String like 'n1|n2|n3...nk|'              
makeIndexList::String->[Int]
makeIndexList [] = []
makeIndexList s =
  let
    (number, rest) =
      (takeWhile (\x -> x /= '|') s, dropWhile (\x -> x /= '|') s)
  in
    [read number] ++ (makeIndexList (drop 1 rest))


predicationFromXmlXN::FFXInput->AnnXMLN->PRED_SYMB
predicationFromXmlXN ffxi anxml = 
  let
    symbolXml = applyXmlFilter (isTag "OMS") (axXml anxml)
    sxname = xshow $ applyXmlFilter (getValue "name") symbolXml
    sxcd = stripFragment $ xshow $ applyXmlFilter (getValue "cd") symbolXml
    {-
    theonode = case getNodeForTheoryName (xnTheorySet ffxi) sxcd of
            Nothing -> error ("No Theory for used predicate (Node) !" ++ sxname)
            (Just n) -> n
    -}
    theoxn = case findByName sxcd (xnTheorySet ffxi) of
            Nothing -> error ("No Theory (" ++ sxcd ++ ") for used predicate (Name) !" ++ sxname ++ " in " ++ show (xnPredsMap ffxi))
            (Just theoxn' ) -> theoxn'
    theopreds = Map.findWithDefault Set.empty (xnName theoxn) (xnPredsMap ffxi) 
    predxnid = case findByName sxname (map fst $ Set.toList theopreds) of
            Nothing ->
              error
                ("No such predicate in Theory! (" ++ show sxname 
                  ++ " in " ++ (show theopreds) ++ ")") 
            (Just predxnid' ) -> predxnid'
    predXNWON = case lookup predxnid $ Set.toList theopreds of
            Nothing -> error "Predicate not found!"
            (Just pxnwon) -> pxnwon
  in
    Qual_pred_name
      (xnWOaToa predxnid)
      (Hets.cv_PredTypeToPred_type $ predTypeXNWONToPredType predXNWON)
      Id.nullRange
                
-- String to Quantifiert...
quantFromName::String->QUANTIFIER
quantFromName s
        | (s == caslSymbolQuantUniversalS) = Universal
        | (s == caslSymbolQuantExistentialS) = Existential
        | (s == caslSymbolQuantUnique_existentialS) = Unique_existential
        | otherwise = error (s++": no such quantifier...")


{-
funKindFromName::String->FunKind
funKindFromName "Total" = Total
funKindFromName "Partial" = Total
funKindFromName s = error ("No such function kind... \""++ s ++"\"")
-}

-- get var decls
getVarDecls::HXT.XmlTrees->[(String, String)]
getVarDecls vt =
  map
    (\t ->
      (
          xshow
            $
            applyXmlFilter
              (getChildren .> isTag "OMATP" .> getChildren .>
                isTag "OMS" .> withValue "name" (/=typeS) .>
                getValue "name"
              )
              [t]
       , xshow
          $
            applyXmlFilter
              (getChildren .> isTag "OMV" .> getValue "name")
              [t]
      )
    )
    (
      (applyXmlFilter (isTag "OMBVAR" .> getChildren .> isTag "OMATTR") vt)
        ::[HXT.XmlTree]
    )


isTermXml::HXT.XmlFilter
isTermXml = isTag "OMV" +++ isTag "OMATTR" +++ isTag "OMA"


isOperatorXml::HXT.XmlFilter
isOperatorXml = isTag "OMATTR" +++ isTag "OMS"


termFromXmlXN::FFXInput->AnnXMLN->(TERM ())
termFromXmlXN ffxi anxml =
  if (applyXmlFilter (isTag "OMV") (axXml anxml)) /= []
    then
      Debug.Trace.trace
        ("Warning: Untyped variable (TERM) from \"" 
          ++ (xshow (axXml anxml))
        ) 
        $
        Simple_id 
          $
          Hets.stringToSimpleId $ xshow 
            $
            applyXmlFilter
              (isTag "OMV" .> getValue "name")
              (axXml anxml)
    else
      if (applyXmlFilter (isTag "OMATTR") (axXml anxml)) /= []
        then
          if
            applyXmlFilter
              (isTag "OMATTR" .> getChildren .>
                isTag "OMATP" .> getChildren .>
                isTag "OMS" .> withSValue "name" "funtype"
              )
              (axXml anxml)
            /= []
            then
              Application (operatorFromXmlXN ffxi anxml) [] Id.nullRange
            else
              Qual_var
                (Hets.stringToSimpleId
                  $
                  xshow
                    $
                    applyXmlFilter
                      (isTag "OMATTR" .> getChildren .>
                        isTag "OMV" .> getValue "name"
                      )
                      (axXml anxml)
                )
                (
                  let
                    varxnsort =
                      xshow
                        $
                        applyXmlFilter
                          (isTag "OMATTR" .> getChildren .>
                            isTag "OMATP" .> getChildren .>
                            isTag "OMS" .> withValue "name" (/=typeS) .>
                            getValue "name"
                          )
                          (axXml anxml)
                    varsort =
                      case
                        findByNameAndOrigin
                          varxnsort
                          (axAnn anxml)
                          (mapSetToSet $ xnSortsMap ffxi)
                      of
                        Nothing ->
                          error
                            ("Cannot find defined sort for \""
                              ++ varxnsort ++"\"" )
                        (Just x) -> xnWOaToa x
                  in
                     varsort
                )
                Id.nullRange
        else
          if (applyXmlFilter (isTag "OMA") (axXml anxml) ) /= []
            then
              let
                operator =
                  operatorFromXmlXN
                    ffxi
                    (AXML
                      (axAnn anxml)
                      ([head
                        $
                        applyXmlFilter
                          (getChildren .> isOperatorXml)
                          (axXml anxml)
                       ]
                      )
                    )
                terms =
                  map
                    (\n -> termFromXmlXN ffxi (AXML (axAnn anxml) [n]))
                    $
                    drop 1
                      $ -- drop out operator
                      applyXmlFilter
                        (getChildren .> isTermXml)
                        (axXml anxml) -- removed 'OrOp'
              in
                if (opName operator) == "PROJ"
                  then
                    Cast
                      (head terms)
                      (Hets.stringToId $ show (head $ tail terms))
                      Id.nullRange
                  else
                    if (opName operator) == "IfThenElse"
                      then
                        let
                          iteChildsX =
                            applyXmlFilter
                              (getChildren .> 
                                (isTag "OMS" +++ isTag "OMATTR" 
                                  +++ isTag "OMA" +++ isTag "OMV")
                              )
                              (axXml anxml)
                          iteCondX = singleitem 2 iteChildsX
                          iteThenX = singleitem 3 iteChildsX
                          iteElseX = singleitem 4 iteChildsX
                          iteCond =
                            formulaFromXmlXN
                              ffxi
                              $
                              debugGO
                                (ffxiGO ffxi)
                                "tFXXNformula"
                                ("Creating Formula for IfThenElse from : "
                                  ++ (xshow iteCondX)
                                )
                                (AXML (axAnn anxml) iteCondX)
                          iteThen = termFromXmlXN ffxi (AXML (axAnn anxml) iteThenX)
                          iteElse = termFromXmlXN ffxi (AXML (axAnn anxml) iteElseX)
                        in
                          debugGO
                            (ffxiGO ffxi)
                            "tFXXN"
                            ("IfThenElse creation...")
                            $ 
                            Conditional
                              iteThen
                              iteCond
                              iteElse
                              Id.nullRange 
                      else
                        Application operator terms Id.nullRange
            else
              if (applyXmlFilter (isTag "OMS") (axXml anxml) ) /= []
                then
                  let
                    operator = 
                      (\x -> debugGO (ffxiGO ffxi)
                        "tFXXNo"
                        ("operator : " ++ (show x))
                        x
                      )
                      $
                      operatorFromXmlXN
                        ffxi
                        anxml
                  in
                    Application operator [] Id.nullRange
                else
                    error
                      ("Impossible to create term from \"" 
                        ++ xshow (axXml anxml) ++"\""
                      ) 
                        

operatorFromXmlXN::FFXInput->AnnXMLN->OP_SYMB
operatorFromXmlXN ffxi anxml =
  let
    symbolXml = applyXmlFilter (isTag "OMS") (axXml anxml)
    sxname = xshow $ applyXmlFilter (getValue "name") symbolXml
    scd = xshow $ applyXmlFilter (getValue "cd") symbolXml
    stheoid =
      case scd of
        ('#':r) -> r
        _ -> scd
    {-
    theonode = case getNodeForTheoryName (xnTheorySet ffxi) scd of
            Nothing -> error ("No Theory for used operator! (" ++ scd ++ ")")
            (Just n) -> n
    -}
    theoxn =
      case findByName stheoid (xnTheorySet ffxi) of
        Nothing ->
          error
            ("No Theory for used operator! (\"" 
              ++ sxname ++ "\" in \"" ++ scd ++ "\" Context : \""
              ++ (take 200 $ xshow (axXml anxml)) ++ "\")"
            )
        (Just theoxn' ) -> theoxn'
    theoops = Map.findWithDefault Set.empty (xnName theoxn) (xnOpsMap ffxi) 
    opxnid = case findByName sxname (map fst $ Set.toList theoops) of
      Nothing ->
        error
          ("No such operator in Theory! (" ++ sxname ++ " in "
            ++ (show theoops) ++ ")")
      (Just opxnid' ) -> opxnid'
    opXNWON = case lookup opxnid $ Set.toList theoops of
      Nothing -> error ("Operator not found!")
      (Just oxnwon) -> oxnwon
  in
    if (stheoid==caslS) 
      then -- eventually there should be an aux. casl-theory while processing...
        Op_name
          $
          debugGO
            (ffxiGO ffxi)
            "oFXXN"
            ("creating casl operator for : " ++ sxname)
            $
            Hets.stringToId sxname
      else
        Qual_op_name
          ((\x ->
            debugGO
              (ffxiGO ffxi)
              "oFXXN"
              ("creating operator for : " ++ sxname ++ " (" ++ (show x) ++ ")")
              x
           )
           (xnWOaToa opxnid)
          )
          (Hets.cv_OpTypeToOp_type $ opTypeXNWONToOpType opXNWON)
          Id.nullRange

opName::OP_SYMB->String
opName (Op_name op) = (show op)
opName (Qual_op_name op _ _) = (show op)

-- this reads back an encapsulated node_name
idToNodeName::Id.Id->NODE_NAME
idToNodeName (Id.Id toks _ _) =
  if (length toks) < 3
    then
      error ("Malformed NODE_NAME-Id : " ++ (show toks))
    else
      (toks!!0, show (toks!!1), read (show (toks!!2)))

