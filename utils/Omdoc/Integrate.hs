{- |
	The Integrate-Module aims at glueing together all needed modules
	for /Hets\<-\>Omdoc/-conversion.
-}
module Integrate where

import qualified HetsInterface as Hets
--import OmdocHXT
import OmdocDevGraph hiding (run, when)
import CASL.Sign
import CASL.Morphism
import CASL.Logic_CASL
import CASL.AS_Basic_CASL
import qualified Common.Id as Id
import qualified Syntax.AS_Library as ASL
import qualified CASL.AS_Basic_CASL as ABC

--import qualified Data.Dynamic as Dyn

import Static.DevGraph
--import qualified Graph as Graph
import qualified Data.Graph.Inductive.Graph as Graph
import qualified Data.Graph.Inductive.Tree as Tree
--import qualified Logic.Grothendieck as Logic.Grothendieck
import CASL.Amalgamability(CASLSign)

import qualified Text.XML.HXT.Parser as HXT hiding (run, trace, when)
import qualified Text.XML.HXT.DOM.XmlTreeTypes as HXTT hiding (when)
import qualified Text.XML.HXT.XPath as XPath

--import qualified Comorphisms.CASL2PCFOL as Com

import qualified Common.Lib.Map as Map
import qualified Common.Lib.Set as Set
import qualified Common.Lib.Rel as Rel

import qualified Common.Result as Result

import qualified Common.AS_Annotation as Ann

import qualified Logic.Logic as Logic
import qualified Logic.Prover as Prover

import Data.Maybe (fromMaybe)
import Data.List (nub, isPrefixOf, isSuffixOf, find)

--import qualified Data.Typeable as Data.Typeable

import qualified Common.GlobalAnnotations as GA

import qualified Driver.Options as DOptions

--import System.IO.Unsafe
import Control.Exception
import Debug.Trace (trace)

import Common.Utils (joinWith)

import qualified System.IO.Error as System.IO.Error
import qualified System.Directory as System.Directory
import qualified System.Posix.Files as System.Posix.Files
import qualified System.Exit as Exit

import qualified System.Environment as Env
import qualified System.Console.GetOpt as GetOpt

import Control.Monad

import Char (toLower, isSpace, isAlpha, isAlphaNum, isDigit, isAscii)

data ImportContext a = ImportContext {
						 importsMap :: Hets.ImportsMap
						,sortsMap :: Hets.SortsMap
						,relsMap :: Hets.RelsMap
						,predsMap :: Hets.PredsMap
						,opsMap :: Hets.OpsMap
						,sensMap :: Hets.SensMap
						,importGraph :: (ImportGraph a)
						}
						

omdocNameXMLNS
	,omdocNameXMLAttr :: String
omdocNameXMLNS = "xml"
omdocNameXMLAttr = "id"
						
theoryNameXMLNS
	,theoryNameXMLAttr :: String
theoryNameXMLNS = "xml"
theoryNameXMLAttr = "id"

axiomNameXMLNS
	,axiomNameXMLAttr :: String
axiomNameXMLNS = ""
axiomNameXMLAttr = "name"
						
sortNameXMLNS
	,sortNameXMLAttr :: String
sortNameXMLNS = ""
sortNameXMLAttr = "name"

symbolTypeXMLNS
	,symbolTypeXMLAttr :: String
	
symbolTypeXMLNS = ""
symbolTypeXMLAttr = "role"

predNameXMLNS
	,predNameXMLAttr :: String
predNameXMLNS = ""
predNameXMLAttr = "name"

opNameXMLNS
	,opNameXMLAttr :: String
opNameXMLNS = ""
opNameXMLAttr = "name"

-- | generate a DOCTYPE-Element for output
mkOmdocTypeElem::
	String -- ^ URI for DTD
	->HXTT.XNode -- ^ DOCTYPE-Element
mkOmdocTypeElem system =
	HXTT.XDTD HXTT.DOCTYPE [
		 (a_name, "omdoc")
		,(k_public, "-//OMDoc//DTD OMDoc V1.2//EN")
		,(k_system, system)
		]

defaultDTDURI::String
-- www.mathweb.org does not provide the dtd anymore (or it is hidden..)
-- defaultDTDURI = "http://www.mathweb.org/src/mathweb/omdoc/dtd/omdoc.dtd"
-- the svn-server does provide the dtd but all my validating software refuses to load it...
-- defaultDTDURI = "https://svn.mathweb.org/repos/mathweb.org/trunk/omdoc/dtd/omdoc.dtd"
-- my private copy of the modular omdoc 1.2 dtd...
-- defaultDTDURI = "/home/hendrik/Dokumente/Studium/Hets/cvs/HetCATScopy/utils/Omdoc/dtd/omdoc.dtd"
-- until dtd-retrieving issues are solved I put the dtd online...
defaultDTDURI = "http://www.tzi.de/~hiben/omdoc/dtd/omdoc.dtd"

-- | generate DOCTYPE-Element with default-DTD-URI 
omdocDocTypeElem::HXTT.XNode
omdocDocTypeElem = mkOmdocTypeElem defaultDTDURI

-- | this function wraps trees into a form that can be written by HXT
writeableTrees::XmlTrees->XmlTree
writeableTrees t =
		(NTree
			((\(NTree a _) -> a) emptyRoot)
			{- ((NTree omdocDocTypeElem [])
				:(NTree (XText "\n")[])
				:t) -}
			t
		)
		
-- | this function wraps trees into a form that can be written by HXT
writeableTreesDTD::String->XmlTrees->XmlTree
writeableTreesDTD dtd' t =
		(NTree
			((\(NTree a _) -> a) emptyRoot)
			((NTree (mkOmdocTypeElem dtd' ) [])
				:(NTree (XText "\n")[])
				:t)
			
		)
		
-- | this function shows Xml with indention
showOmdoc::XmlTrees->IO XmlTrees
showOmdoc t = HXT.run' $
	HXT.writeDocument
		[(a_indent, v_1), (a_issue_errors, v_1)] $
		writeableTrees t
		
-- | this function shows Xml with indention
showOmdocDTD::String->XmlTrees->IO XmlTrees
showOmdocDTD dtd' t = HXT.run' $
	HXT.writeDocument
		[(a_indent, v_1), (a_issue_errors, v_1)] $
		writeableTreesDTD dtd' t

-- | this function writes Xml with indention to a file
writeOmdoc::XmlTrees->String->IO XmlTrees
writeOmdoc t f = HXT.run' $
	HXT.writeDocument
		[(a_indent, v_1), (a_output_file, f)] $
		writeableTrees t
		
-- | this function writes Xml with indention to a file
writeOmdocDTD::String->XmlTrees->String->IO XmlTrees
writeOmdocDTD dtd' t f = HXT.run' $
	HXT.writeDocument
		[(a_indent, v_1), (a_output_file, f)] $
		writeableTreesDTD dtd' t

-- | processing options for getopt		
data PO = POInput String | POInputType String | POOutput String | POOutputType String | POShowGraph | POLib String | POSandbox String | POHelp | PODTDURI String | PODebug | PONewOutput | PODisableDTD
		
processingOptions::[GetOpt.OptDescr PO]
processingOptions =
	[
	  GetOpt.Option ['i'] ["input"] (GetOpt.ReqArg POInput "INPUT") "File to read from"
	, GetOpt.Option ['r'] ["input-type"] (GetOpt.ReqArg POInputType "INPUTTYPE (casl, omdoc, env)") "Type of input"
	, GetOpt.Option ['o'] ["output"] (GetOpt.ReqArg POOutput "OUTPUT") "File to write to"
	, GetOpt.Option ['w'] ["output-type"] (GetOpt.ReqArg POOutputType "OUTPUTTYPE (omdoc, env, fullenv)") "Type of output"
	, GetOpt.Option ['l'] ["library"] (GetOpt.ReqArg POLib "LIBDIR") "Directory to search for input files"
	, GetOpt.Option ['g'] ["showgraph"] (GetOpt.NoArg POShowGraph) "Show Graph"
	, GetOpt.Option ['a'] ["all-libs"] (GetOpt.OptArg (POSandbox . (fromMaybe "")) "OUTDIR") "Output all used libraries [to dir]"
	, GetOpt.Option ['h'] ["help"] (GetOpt.NoArg POHelp) "print this info"
	, GetOpt.Option ['d'] ["dtd-uri"] (GetOpt.ReqArg PODTDURI "DTDURI") "URI for OMDoc-DTD"
	, GetOpt.Option [] ["debug"] (GetOpt.NoArg PODebug) "enable debugging-messages"
	, GetOpt.Option ['n'] ["new-output"] (GetOpt.NoArg PONewOutput) "use new output (possibly buggy, no read-in-support yet)"
	, GetOpt.Option [] ["disable-dtd"] (GetOpt.NoArg PODisableDTD) "disable putting DTD-location in OMDoc-Output"
	]
	
usageString::String
usageString = GetOpt.usageInfo "Integrate [-i <input>] [-o <output>] [-l dir] [-g] [-a[<directory>]] [-d <dtd-uri>]" processingOptions

-- | convert a file name that may have a suffix to a library name
-- taken from AnalysisLibrary (not exported)
fileToLibName :: DOptions.HetcatsOpts -> FilePath -> ASL.LIB_NAME
fileToLibName opts efile =
    let path = DOptions.libdir opts
        file = DOptions.rmSuffix efile -- cut of extension
        nfile = dropWhile (== '/') $         -- cut off leading slashes
                if isPrefixOf path file
                then drop (length path) file -- cut off libdir prefix
                else file
    in ASL.Lib_id $ ASL.Indirect_link nfile Id.nullRange
	
data FileType = FTCASL | FTOMDoc | FTEnv | FTFullEnv | FTNone
	deriving Eq
	
instance Show FileType where
	show FTCASL = "CASL"
	show FTOMDoc = "OMDoc"
	show FTEnv = "Environment"
	show FTFullEnv = "Full-Environment"
	show FTNone = "None"
	
instance Read FileType where
	readsPrec _ r =
		let
			wsdroplen = length $ takeWhile Char.isSpace r
		in
			(\s ->
				if isPrefixOf "casl" s then [(FTCASL, drop (4+wsdroplen) r)]
				else
				if isPrefixOf "omdoc" s then [(FTOMDoc, drop (5+wsdroplen) r)]
				else
				if isPrefixOf "xml" s then [(FTOMDoc, drop (3+wsdroplen) r)]
				else
				if isPrefixOf "env" s then [(FTEnv, drop (3+wsdroplen) r)]
				else
				if isPrefixOf "fenv" s then [(FTFullEnv, drop (4+wsdroplen) r)]
				else
				if isPrefixOf "none" s then [(FTNone, drop (4+wsdroplen) r)]
				else
				if isPrefixOf "-" s then [(FTNone, drop (1+wsdroplen) r)]
				else
					[]
			) $ map Char.toLower $ drop wsdroplen r 

type FileTypes = [FileType]
	
supportedInput::FileTypes
supportedInput = [FTCASL, FTOMDoc, FTFullEnv, FTEnv]

supportedOutput::FileTypes
supportedOutput = [FTOMDoc, FTEnv, FTFullEnv, FTNone]

-- | tries to determine the type of a file by its extension
-- "-" and "none" lead to FTNone
fileType::String->Maybe FileType
fileType s =
	let
		suffix = reverse $ takeWhile (/='.') $ reverse s
		parse = readsPrec 0 suffix
	in
		case parse of
			[(ft, "")] -> Just ft
			_ -> Nothing

-- | some basic interface for command-line use... 
-- you can read in CASL, OMDoc or Environments (ATerm) and ouput OMDoc or
-- Environments.
-- Currently there are two forms of environments. One that is the output from
-- Hets - a single GlobalContext - and a second that is a full environment 
-- with the name of the library that was read in and all related GlobalContexts.
-- Actually the latter is not really what is wanted and will be removed when
-- better ways of retrieving related DGraphs are developed.
main::IO ()
main =
	do
		args <- Env.getArgs
		(options, nonoptions) <-
			case GetOpt.getOpt GetOpt.Permute processingOptions args of
				(o' ,n,[]) -> return (o' ,n)
				(_,_,errs) -> ioError (userError (concat errs ++ usageString))
		when
			-- no arguments or Help requested
			(	((length args) == 0) ||
				((length
					(filter
						(\op -> case op of POHelp -> True; _ -> False)
						options)
					) /= 0)
			)
			(do
				-- print usage and exit
				putStrLn usageString
				Exit.exitWith (Exit.ExitSuccess))
		-- filter out options
		inputopts <- return $ filter
			(\op -> case op of POInput _ -> True; _ -> False)
			options
		inputtypeopts <- return $ filter
			(\op -> case op of POInputType _ -> True; _ -> False)
			options
		outputopts <- return $ filter
			(\op -> case op of POOutput _ -> True; _ -> False)
			options
		outputtypeopts <- return $ filter
			(\op -> case op of POOutputType _ -> True; _ -> False)
			options
		alloutopts <- return $ filter
			(\op -> case op of POSandbox _ -> True; _ -> False)
			options
		showgraphopts <- return $ filter
			(\op -> case op of POShowGraph -> True; _ -> False)
			options
		dtduriopts <- return $ filter
			(\op -> case op of PODTDURI _ -> True; _ -> False)
			options
		debugopts <- return $ filter
			(\op -> case op of PODebug -> True; _ -> False)
			options
		debug <- return $ (case debugopts of [] -> False; _ -> True)
		newoutputopts <- return $ filter
			(\op -> case op of PONewOutput -> True; _ -> False)
			options
		newoutput <- return $ (case newoutputopts of [] -> False; _ -> True)
		disabledtdopts <- return $ filter
			(\op -> case op of PODisableDTD -> True; _ -> False)
			options
		disabledtd <- return $ (case disabledtdopts of [] -> False; _ -> True)
		input <- return $ case inputopts of
					[] -> case nonoptions of
						[] -> "-"
						_ -> head nonoptions
					((POInput s):_) -> s
					_ -> error "wierd entry for input..."
		-- determine input type from parameter or filename
		inputtype <-
			case inputtypeopts of
				[] ->
					do
					when
						debug
						(putStrLn "No Input-Type given. Trying to find out...")
					mft <- return $ fileType input
					case mft of
						(Just ft) -> return ft
						Nothing ->
							ioError (userError "Cannot determine Input-Type!")
				((POInputType s):_) -> return $ read s
				_ -> error "wierd entry for inputtype..."
		when
			debug
			(putStrLn ("Input-Type is : " ++ (show inputtype)))
		-- check if this type is supported
		unless
			(elem inputtype supportedInput)
			(ioError (userError "Unsupported type of input..."))
		output <- return $ case outputopts of
					[] -> ""
					((POOutput s):_) -> s
					_ -> error "wierd entry for output..."
		-- determine output type from parameter or filename
		outputtype <- if output /= []
			then
				case outputtypeopts of
					[] ->
						do
						when
							debug
							(putStrLn
								"No Output-Type given. Trying to find out..."
							)
						mft <- return $ fileType output
						case mft of
							(Just ft) -> return ft
							Nothing ->
								ioError
									(userError "Cannot determine Output-Type!")
					((POOutputType s):_) -> return $ read s
					_ -> error "wierd entry for outputtype..."

			else
				return FTNone
		when
			debug
			(putStrLn ("Output-Type is : " ++ (show outputtype)))
		-- check if this type is supported
		unless
			(elem outputtype supportedOutput)
			(ioError (userError "Unsupported type of output..."))
		sandbox <- return $ case alloutopts of
			[] -> ""
			((POSandbox s):_) -> s
			_ -> error "wierd entry for sandbox..."
		when
			debug
			(putStrLn ("Sandbox set to : \"" ++ sandbox++ "\""))  
		doshow <- return $ (length showgraphopts) /= 0
		when
			debug
			(putStrLn ("Graph-Output : " ++ (if doshow then "Yes" else "No"))) 
		dtduri <- return $ case dtduriopts of
			[] -> defaultDTDURI
			((PODTDURI s):_) -> s
			_ -> error "wierd entry for dtduri..."
		when
			(debug && disabledtd)
			(putStrLn "DTD-Output disabled...")
		searchpath <- return $ map (\(POLib s) -> s) $ filter (\o' -> case o' of (POLib _) -> True; _ -> False) options
		when
			debug
			(putStrLn
				((show inputtype) ++ "(" ++ input ++ ") -> "
					++ (show outputtype) ++ "(" ++ output ++ ")"))
		-- get input
		(ln, dg, lenv) <-
			case ((\inty -> case inty of FTFullEnv -> FTEnv; _ -> inty) inputtype) of
				FTOMDoc ->
						do
						when debug (putStrLn ("Trying to load omdoc-file..."))
						ig <- makeImportGraph input searchpath
						(return $ dGraphGToLibEnv $ hybridGToDGraphG $
							processImportGraph ig)
				FTCASL->
						do
						when debug (putStrLn ("Trying to load casl-file..."))
						menv <- Hets.run input
						(ln' ,lenv' ) <- case menv of
							Nothing ->
								ioError
									(userError "Could not load CASL-File...")
							(Just env) -> return env
						dg <- case Map.lookup ln' lenv' of
							Nothing ->
								ioError
									(userError "Could not get DGraph...")
							(Just gc) -> return $ devGraph gc
						return (ln' ,dg,lenv' )
				FTEnv ->
						-- currently environment processing is done in one
						-- section to handle full and non-full environments
						-- this may change...
						do
						when debug (putStrLn "Trying to load env-file...")
						s <- readFile input
						-- parse input for both variants (lazy)
						(Result.Result _ menv) <-
							return
								((Hets.fromShATermString s)::(Result.Result (ASL.LIB_NAME, LibEnv)))
						(Result.Result _ mgc) <-
							return
								((Hets.fromShATermString s)::(Result.Result GlobalContext))
						-- parser will use error if it is not it's type...
						(Control.Exception.catch
							(
								do
								when
									debug
									(putStr "...as full environment...")
								(return menv) >>= \x -> case x of
									(Just me) -> return me >>=  
										\me' @(_, melenv) ->
										do
											 -- evaluate to trigger error
											_ <- return $! Map.size $! melenv
											return $ lnLibEnvToLnDGLibEnv me' 
									Nothing ->
										error "Error processing environment..."
							)
							(\_ ->
								-- if the first parser triggers this exception
								-- the next parser tries the other variant
							  Control.Exception.catch
								  (
									do
									when
										debug
										(putStr
											"failed.\n...as globalcontext...")
									(return mgc) >>= \x -> case x of
										(Just gc) ->
												do
													lname <-
														return
															(fileToLibName Hets.dho input)
													 -- evaluate to trigger error
													_ <-
														return $! Graph.nodes $!
															(devGraph gc)
													return
														(lname,
														(devGraph gc),
														(Map.fromList
															[(lname, gc)]
															)
														)
										Nothing -> error "Error processing environment..."
									)
								  (\_ ->
								  	-- if this exception is triggered, no parser
									-- was able to process the file...
								  	when
										debug
										(putStrLn "failed.")
									>> ioError
										(userError
											"Unable to process env-file..."
										)
									)
							)) >>= \e -> -- one of the parsers succeeded
								when
									debug
									(putStrLn "success.")
								>> return e 
				_ -> -- no input (?)
						do
						ioError (userError "No input to process...")
		when doshow
				(when debug (putStrLn "Showing Graph...") >>
				showdg (ln,lenv))
		case outputtype of
			FTOMDoc ->
				do
				when debug (putStrLn ("Outputting OMDoc..."))
				when (debug && newoutput) (putStrLn ("using new output (you cannot read this in again yet)"))
				omdoc <- (if newoutput then devGraphToOmdocCMPIOXN else devGraphToOmdocCMPIO) dg (stripLibName (show ln))
				case output of
					"" -> return ()
						-- show/writeOmdocDTD :: IO XmlTrees --> return ()
					"-" -> (if disabledtd then showOmdoc else showOmdocDTD dtduri) omdoc >> return ()
					_ -> (if disabledtd then writeOmdoc else writeOmdocDTD dtduri) omdoc output >> return ()
				case sandbox of
					"" -> return ()
					_ ->
							let
								igdg = libEnvToDGraphG (ln,dg,lenv)
								igx = dGraphGToXmlG igdg
							in
								do
									writeXmlG dtduri igx sandbox
			FTEnv -> -- on output separate functions are used for environment
				do
				when debug (putStrLn ("Outputting GlobalContext..."))
				ga <- case Map.lookup ln lenv of
					Nothing -> ioError (userError "Lookup failed...")
					(Just ga' ) -> return ga'
				case output of
					"" -> return ()
					"-" ->
						Hets.toShATermString ga >>= putStrLn
					_ ->
						Hets.writeShATermFile output ga
			FTFullEnv ->
				do
				when debug (putStrLn ("Outputting Full Environment..."))
				case output of
					"" -> return ()
					"-" ->
						Hets.toShATermString (ln,lenv) >>= putStrLn
					_ ->
						Hets.writeShATermFile output (ln,lenv)
			_ ->
				return ()
		return ()
		
lnLibEnvToLnDGLibEnv::(ASL.LIB_NAME, LibEnv)->(ASL.LIB_NAME, DGraph, LibEnv)
lnLibEnvToLnDGLibEnv (ln,lenv) =
	let
		dg = case Map.lookup ln lenv of
			(Just gc) -> devGraph gc
			Nothing -> error "Cannot lookup DGraph in LibEnv!"
	in
		(ln, dg, lenv)
		
removeSuffix::String->String
removeSuffix s = case dropWhile (/='.') $ reverse s of
	[] -> s
	(_:r) -> reverse r

-- | this does not really work right now 'in the wild'...
libEnvFromEnvironment::DOptions.HetcatsOpts->FilePath->IO (Maybe (ASL.LIB_NAME, LibEnv))
libEnvFromEnvironment ho f =
	let
		asCASL = removeSuffix f ++ ".casl"
	in
	do
		fileExists <- System.Directory.doesFileExist asCASL
		unless
			fileExists
			(do
				writeFile asCASL "dummy"
				System.Posix.Files.touchFile f)
		menv <- Hets.anaLib ho asCASL	-- anaLib will look for the environment
										-- and see it is more recent...
		unless
			fileExists
			(do System.Directory.removeFile asCASL)
		return menv
			
		
libEnvFromOmdocFile::String->[String]->IO (ASL.LIB_NAME, DGraph, LibEnv)
libEnvFromOmdocFile f l = makeImportGraph f l >>= return . dGraphGToLibEnv . hybridGToDGraphG . processImportGraph

-- | loads an omdoc-file and returns it even if there are errors
-- fatal errors lead to IOError
loadOmdoc ::String->(IO XmlTrees)
loadOmdoc f =
	do
		tree <- (
			HXT.run' $
			HXT.parseDocument
				[
					(a_source, f)
					,(a_validate, v_0) -- validation is nice, but HXT does not give back even a partial document then...
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
				
loadOmdocForXPath :: String->(IO XmlTrees)
loadOmdocForXPath f =
	do
		run' $ parseDocument [
			 (a_source, f)
			,(a_validate,v_0)
			,(a_issue_errors, v_0)
			,(a_check_namespaces,v_1)
			] emptyRoot
						
stripLibName::String->String
stripLibName = last . explode "/"

-- | Convert a DevGraph to OMDoc-XML with given xml:id attribute
devGraphToOmdocCMPIO::Static.DevGraph.DGraph->String->IO HXT.XmlTrees
devGraphToOmdocCMPIO dg name' =
	do
		dgx <- devGraphToXmlCMPIO dg
		return (
			(HXT.etag "omdoc" += ( qualattr omdocNameXMLNS omdocNameXMLAttr name'
					+++ xmlNL +++ dgx )) emptyRoot
			)

-- | Convert a DevGraph to OMDoc-XML with given xml:id attribute
devGraphToOmdocCMPIOXN::Static.DevGraph.DGraph->String->IO HXT.XmlTrees
devGraphToOmdocCMPIOXN dg name' =
	do
		dgx <- devGraphToXmlCMPIOXmlNamed dg
		return (
			(HXT.etag "omdoc" += ( qualattr omdocNameXMLNS omdocNameXMLAttr name'
					+++ xmlNL +++ dgx )) emptyRoot
			)
			
-- | Convert a DevGraph to OMDoc-XML with given xml:id attribute
devGraphToOmdoc::Static.DevGraph.DGraph->String->HXT.XmlTrees
devGraphToOmdoc dg name' = (HXT.etag "omdoc" += ( qualattr omdocNameXMLNS omdocNameXMLAttr name'
				+++ xmlNL +++ devGraphToXml dg )) emptyRoot

-- | Convert a DevGraph to an XML-Representation (without omdoc parent)				
devGraphToXmlCMPIO::Static.DevGraph.DGraph->IO (HXT.XmlTree->HXT.XmlTrees)
devGraphToXmlCMPIO dg =
		let
			(onlynodenameset, onlyrefnameset) = Hets.getNodeNamesNodeRef dg
			nodenameset = Set.union onlynodenameset onlyrefnameset
			nodenamemap = Map.fromList $ Set.toList nodenameset
			--namenodemap = Map.fromList $ map (\(a,b) -> (b,a)) $ Map.toList nodenamemap
			--nodenames = Set.fromList $ map (\(_,a) -> a) $ Set.toList nodenameset
			sorts' = Hets.getSortsWithNodeNames dg
			rels' = Hets.getRelationsWithNodeNames dg
			preds' = Hets.getPredMapsWithNodeNames dg
			ops' = Hets.getOpMapsWithNodeNames dg
			sens = Hets.getSentencesWithNodeNames dg
			mimports = Hets.getNodeImportsNodeNames dg
			--imports = Map.map (Set.map fst) mimports
		in
		    foldl (\dgxio (node, name' ) ->
		    	let
					nSorts = Map.findWithDefault Set.empty name' sorts' 
					-- OMDocS 'insort' is opposite to CASL-Sort-Relation 
					nInsorts = Rel.transpose $ Map.findWithDefault Rel.empty name' rels'
					nInsortMap = foldl (\m (a,b) -> 
						Map.insert a (Set.insert b (Map.findWithDefault Set.empty a m)) m
						) Map.empty $ Rel.toList nInsorts
					nPreds = Map.findWithDefault Map.empty name' preds'  
					nOps = Map.findWithDefault Map.empty name' ops'
					nSens = Map.findWithDefault Set.empty name' sens
					(_, sortgen) = partitionSensSortGen $ Set.toList nSens
					constructors = makeConstructors sortgen
					
					-- sort-imports (not all imports)
					nImports = Map.findWithDefault Set.empty name' mimports
					-- what adts are needed (insort, cons or both)
					adtsorts = nub $ (map (\ (a,_) -> a) $ Map.toList nInsortMap) ++
						(map (\(a,_) -> a) $ Map.toList constructors)
					-- remove everything that came from a morphism
					(realSorts, realOps, realPreds) = foldl (\(rs, ro, rp) (_,mmm) ->
						case mmm of
							Nothing -> (rs, ro, rp)
							(Just mm) -> (Hets.removeMorphismSorts mm rs,
								Hets.removeMorphismOps mm ro,
								Hets.removeMorphismPreds mm rp)
							) (nSorts, nOps, nPreds) $ Set.toList nImports
				in
					do 
					dgx <- dgxio
					sensxml <- (wrapFormulasCMPIO mimports sorts' preds' ops' name' $ Set.toList nSens)
					return (
						dgx +++
						(HXT.etag "theory" += (qualattr theoryNameXMLNS theoryNameXMLAttr name' ))
						+= (
						   (foldl (\ix (i,mmm) -> ix +++ xmlNL +++ importToXml i +=
								(
								case mmm of
									Nothing -> HXT.txt ""
									(Just mm) ->
										morphismMapToXml mm i name'
										+++
										xmlNL
								)
							) (HXT.txt "") $ Set.toList nImports)
						   +++
						   (foldl (\sx s -> sx +++ xmlNL +++ sortToXml s) (HXT.txt "") $ Set.toList realSorts) --nSorts)
						   +++
						   -- adt-generation needs some optimization...
						   (foldl (\adtx sort -> adtx +++ xmlNL
							+++ (
								let 
									sortrelation = (\a -> (sort, a)) $ Map.findWithDefault Set.empty sort nInsortMap
									cons = createAllConstructors $ Map.toList $ Map.findWithDefault Map.empty sort constructors
								in
									createADT sortrelation cons
								)
							) (HXT.txt "") adtsorts)
						   +++
						   (foldl (\px p -> px +++ xmlNL +++ predicationToXml mimports sorts' name' p)
							(HXT.txt "") $ Map.toList realPreds) --nPreds)
						   +++
						   (foldl (\px o' -> px +++ xmlNL +++ operatorToXml mimports sorts' name' o' )
							(HXT.txt "") $ Map.toList realOps) --nOps)
						   +++
						   sensxml
						   +++ xmlNL
						   )
						+++ xmlNL
						-- make private data for all incoming links
						+++ inDGToXml dg node nodenamemap 
						+++ xmlNL
						)
				) (return (refsToCatalogue dg +++ xmlNL)) $ Set.toList onlynodenameset
				
mapToSetToTupelList::(Container c b)=>Map.Map a c->[(a,b)]
mapToSetToTupelList mapping =
	foldl (\l (a, s) ->
		foldl (\l' i ->
			l' ++ [(a, i)]
			) l (getItems s)
		) [] (Map.toList mapping)
		
makePresentationFor::XmlName->String->HXT.XmlFilter
makePresentationFor xname presstring =
	HXT.etag "presentation" += (
		(HXT.sattr "for" xname)
		+++ HXT.etag "use" += (
			(HXT.sattr "format" "Hets")
			+++ (HXT.txt presstring)
			)
		)

	
devGraphToXmlCMPIOXmlNamed::Static.DevGraph.DGraph->IO (HXT.XmlTree->HXT.XmlTrees)
devGraphToXmlCMPIOXmlNamed dg =
	let
		(onlynodenameset, onlyrefnameset) = Hets.getNodeDGNamesNodeRef dg
		(onlynodexmlnamelist, xmlnames_onxnl) = createXmlNames nodeTupelToNodeName [] (Set.toList onlynodenameset)
		(onlyrefxmlnamelist, xmlnames_orxnl) = createXmlNames nodeTupelToNodeName xmlnames_onxnl (Set.toList onlyrefnameset)
		nodenameset = Set.union onlynodenameset onlyrefnameset
		nodexmlnameset = Set.fromList (onlynodexmlnamelist ++ onlyrefxmlnamelist)
		nodenamemap = Map.fromList $ Set.toList nodenameset
		sortswomap = Hets.getSortsWOWithNodeDGNamesWO dg
		relswomap= Hets.getRelationsWOWithNodeDGNamesWOSMDGWO dg sortswomap
		predswomap = Map.map mapToSetToTupelList $ Hets.getPredMapsWOWithNodeDGNamesWO dg
		opswomap = Map.map mapToSetToTupelList $ Hets.getOpMapsWOWithNodeDGNamesWO dg
		senswomap = Hets.getSentencesWOWithNodeDGNamesWO dg
		-- sorts
		(xmlnamedsortswomap, xmlnames_sm) =
			(processSubContents
				(\xmlnames c -> uniqueXmlNamesContainerWONExt
					xmlnames
					show
					c
					(pSCStrip id)
					(\(k, swo) xname -> (k,XmlNamed swo xname))
				)
				xmlnames_orxnl
				sortswomap)::(Map.Map Hets.NODE_NAMEWO (Set.Set (XmlNamed Hets.SORTWO)), XmlNameList)
		-- relations -- maybe not needed with xmlnames...
		xmlnames_rm = xmlnames_sm
		xmlnamedrelswomap =
			foldl
				(\relmap' theory ->
					let
						theorysorts = Map.findWithDefault Set.empty theory xmlnamedsortswomap
					in
						Map.insert
							theory
							(Rel.fromList
								(map (\(a,b) ->
									let
										a' = case Set.toList (Set.filter (\i -> (xnItem i) == a) theorysorts) of
											[] -> error "No such sort in theory..."
											(i:_) -> XmlNamed a (xnName i)
										b' = case Set.toList (Set.filter (\i -> (xnItem i) == b) theorysorts) of
											[] -> error "No such sort in theory..."
											(i:_) -> XmlNamed b (xnName i)
									in
										(a' , b' )
									) (Rel.toList (Map.findWithDefault Rel.empty theory relswomap))))
							relmap' 
				)
				Map.empty
				(Map.keys relswomap)
		-- predicates
		(xmlnamedpredswomap, xmlnames_pm) =
			(processSubContents
				(\xmlnames c -> uniqueXmlNamesContainerWONExt
					xmlnames
					show
					c
					(pSCStrip (\(pidwo,_) -> pidwo))
					(\(k, (pidwo, pset)) xname -> (k, (XmlNamed pidwo xname, pset)))
				)
				xmlnames_orxnl
				predswomap)::(Map.Map Hets.NODE_NAMEWO [(XmlNamedWONId, PredType)], XmlNameList)
				--predswomap)::(Map.Map Hets.NODE_NAMEWO (Map.Map (XmlNamed Hets.IdWO) (Set.Set PredType)), XmlNameList)
		-- operators
		(xmlnamedopswomap, xmlnames_om) =
			(processSubContents
				(\xmlnames c ->
					uniqueXmlNamesContainerWONExt
						xmlnames
						show
						c
						(pSCStrip (\(oidwo,_) -> oidwo))
						(\(k,(oidwo,oset)) xname -> (k, (XmlNamed oidwo xname, oset)))
				)
				xmlnames_pm
				opswomap)::(Map.Map Hets.NODE_NAMEWO [(XmlNamedWONId, OpType)], XmlNameList)
--				opswomap)::(Map.Map Hets.NODE_NAMEWO (Map.Map (XmlNamed Hets.IdWO) (Set.Set OpType)), XmlNameList)
		-- sentences
		(xmlnamedsenswomap, xmlnames_senm) =
			(processSubContents
				(\xmlnames nsensset ->
					uniqueXmlNamesContainerWONExt
						xmlnames
						Ann.senName
						nsensset
						(pSCStrip id)
						(\(k, senswo) xname -> (k, XmlNamed senswo xname))
				)
				xmlnames_om
				senswomap)::(Map.Map Hets.NODE_NAMEWO (Set.Set (XmlNamed Hets.SentenceWO)), XmlNameList)
		importsmap = Hets.getNodeImportsNodeDGNames dg
	in
		foldl (\xio xnodetupel ->
			let
				theoname = xnName xnodetupel
				(nodenum, nodename) = xnItem xnodetupel
				theosorts = Map.findWithDefault Set.empty (Hets.mkWON nodename nodenum) xmlnamedsortswomap
				realsorts = Set.filter (\i -> (xnWOaToO i) == nodenum) theosorts
				realsortswo = Set.map (xnItem) realsorts
				theorels = Map.findWithDefault Rel.empty (Hets.mkWON nodename nodenum) relswomap
				-- only keep relations that include at least one sort from the
				-- current theory
				realrels = Rel.fromList $ filter (\(a,b) ->
					(Set.member a realsortswo) || (Set.member b realsortswo)
					) (Rel.toList theorels)
				insorts = Rel.transpose realrels 
				insortmap =
					foldl (\m (a,b) ->
						Map.insert
							a
							(Set.insert b (Map.findWithDefault Set.empty a m))
							m
						) Map.empty (Rel.toList insorts)
				theopreds = Map.findWithDefault [] (Hets.mkWON nodename nodenum) xmlnamedpredswomap
				realtheopreds = filter (\(idxnwon, _) -> (xnWOaToO idxnwon) == nodenum) theopreds
				theoops = Map.findWithDefault [] (Hets.mkWON nodename nodenum) xmlnamedopswomap
				realtheoops = filter (\(idxnwon, _) -> (xnWOaToO idxnwon) == nodenum) theoops
				theosens = Map.findWithDefault Set.empty (Hets.mkWON nodename nodenum) xmlnamedsenswomap
				realtheosens = Set.filter (\i -> (xnWOaToO i) == nodenum) theosens
				(_, sortgenxn) = partitionSensSortGenXN (Set.toList realtheosens)
				(constructors, xmlnames_cons) = makeConstructorsXN theosorts xmlnames_senm sortgenxn
				adtsorts = Map.keys insortmap ++ (map (\(a,_) -> xnItem a) (Map.toList constructors))
				theoimports = Map.findWithDefault Set.empty nodename importsmap
				theopredsxn = map (\(k,p) -> (k, predTypeToPredTypeXNWON theosorts p)) theopreds
				theoopsxn = map (\(k,op) -> (k, opTypeToOpTypeXNWON theosorts op)) theoops
				sensxmlio = wrapFormulasCMPIOXN (PFInput nodexmlnameset theosorts theopredsxn theoopsxn) (Set.toList realtheosens) 
			in
				do
				x <- xio
				sensxml <- sensxmlio
				return $ x +++ xmlNL +++ HXT.etag "theory" += (
					(qualattr "xml" "id" theoname) +++
					-- presentation
					makePresentationFor
						theoname
						(idToString $ nodeNameToId (snd (xnItem xnodetupel))) +++
					xmlNL +++
					-- imports/morphisms
					-- I still need to find a way of modelling Hets-libraries
					-- in Omdoc-Imports...
					(foldl (\x' (nodename' , mmm) ->
						let
							nodenamex = case Set.toList $ Set.filter (\i -> (snd (xnItem i)) == nodename' ) nodexmlnameset of
								[] -> error "Import from Unknown node..."
								(l:_) -> xnName l
						in
							x' +++
							HXT.etag "imports" += (
								(HXT.sattr "from" ("#" ++ nodenamex)) +++
								(
									case mmm of
										(Just mm) ->
											morphismMapToXml mm nodenamex theoname
										Nothing -> HXT.txt ""
								)
								) +++
							xmlNL
						) (HXT.txt "") (Set.toList theoimports)
					) +++
					-- sorts
					(Set.fold (\xnwos x' ->
						x' +++
						(sortToXmlXN (xnWOaToXNa xnwos)) +++
						xmlNL +++
						makePresentationFor
							(xnName xnwos)
							(idToString (xnWOaToa xnwos)) +++
						xmlNL
						) xmlNL realsorts) +++
					-- adts
					{- 
					   no presentation needed for adts as they are 
					   generated from a) relations and b) sentences.
					   relations have their presentation via sort-definition
					   and sentences get their own presentation tags.
					-}
					(foldl (\x' sortwo ->
						let
							insortset = Map.findWithDefault Set.empty sortwo insortmap
							sortxn = case find (\i -> Hets.sameOrigin sortwo (xnItem i) && sortwo == (xnItem i)) (Set.toList theosorts) of
								Nothing -> error "Sort in relation but not in theory..."
								(Just sortxn' ) -> xnWOaToXNa sortxn'
							insortsetxn = Set.map (\i ->
								case find (\j -> Hets.sameOrigin i (xnItem j) && i == (xnItem j)) (Set.toList theosorts) of
									Nothing -> error "Sort in relation but not in theory..."
									(Just sortxn' ) -> xnWOaToXNa sortxn'
								) insortset
							constructorx = createAllConstructorsXN nodexmlnameset $ Map.toList $ Map.findWithDefault Map.empty (XmlNamed sortwo (xnName sortxn)) constructors
						in
							x' +++ createADTXN (sortxn, insortsetxn) constructorx +++ xmlNL
						) xmlNL adtsorts) +++
					-- predicates
					(foldl
						(\x' (pxnid, p) ->
							let
								px = predTypeToPredTypeXNWON theosorts p 
							in
								x' +++
								predicationToXmlXN
									nodexmlnameset
									(pxnid, px) +++
								xmlNL +++
								makePresentationFor
									(xnName pxnid)
									(idToString $ xnWOaToa pxnid) +++
								xmlNL
						)
						(HXT.txt "")
						realtheopreds
					) +++
					-- operators
					(foldl
						(\x' (oxnid, op) ->
							let
								ox = opTypeToOpTypeXNWON theosorts op 
							in
								x' +++ 
								operatorToXmlXN
									nodexmlnameset
									(oxnid, ox) +++
								xmlNL +++
								makePresentationFor
									(xnName oxnid)
									(idToString $ xnWOaToa oxnid) +++
								xmlNL
						)
						(HXT.txt "")
						realtheoops
					) +++
					-- sentences
					sensxml +++
					xmlNL +++
					-- this constructs Hets-internal links as private data (but uses xmlnames for reference)
					inDGToXmlXN dg nodenum nodexmlnameset
					)
					-- when constructing the catalogues a reference to the xmlname used in _this_ document is used
					-- it is very likely possible, that this theory has another name in real life (unless there are no name-collisions)
			) (return $ refsToCatalogueXN dg nodexmlnameset +++ xmlNL) onlynodexmlnamelist 
				
	where
	nodeTupelToNodeName::(a, NODE_NAME)->String
	nodeTupelToNodeName = nodeToNodeName . snd
	
	nodeToNodeName::NODE_NAME->String
	nodeToNodeName = (\nn ->
							let
								nodename = showName nn
							in
								if (length nodename) == 0
									then
										"AnonNode_"
									else
										nodename
							)
							
type WithOriginTheory a = Hets.WithOrigin a String

type XmlNamedWO a b = XmlNamed (Hets.WithOrigin a b)
type XmlNamedWON a = XmlNamedWO a Graph.Node

type XmlNamedWONSORT = XmlNamedWON SORT

xnWOaToXNa::XmlNamedWO a b->XmlNamed a
xnWOaToXNa a = XmlNamed (Hets.woItem (xnItem a)) (xnName a)

xnWOaToa::XmlNamedWO a b->a
xnWOaToa a = Hets.woItem (xnItem a)

xnWOaToO::XmlNamedWO a b->b
xnWOaToO a = Hets.woOrigin (xnItem a)

-- just an alias to complete this
xnWOaToWOa::XmlNamedWO a b->Hets.WithOrigin a b
xnWOaToWOa a = xnItem a

{-
nodeSetWOToNodeSetTheory::(Ord a)=>Set.Set (XmlNamed Hets.NODE_NAMEWO)->Set.Set (XmlNamed (Hets.WithOriginNode a))->Set.Set (XmlNamed (WithOriginTheory a))
nodeSetWOToNodeSetTheory nodenameset tonameset =
	Set.map (\(XmlNamed (Hets.WithOrigin { Hets.woItem = aitem , Hets.woOrigin = aorigin }) axname) ->
		let
			origins = Set.filter (\o' -> (Hets.woOrigin (xnItem o' )) == aorigin) nodenameset
		in
			case Set.toList origins of
				[] -> error "!!!"
				((XmlNamed _ xname):_) ->
					XmlNamed (mkWOT aitem xname) axname
			) tonameset
	-}		
data PredTypeXNWON = PredTypeXNWON {predArgsXNWON :: [XmlNamedWON SORT]}
	deriving (Show, Eq, Ord)
	
data OpTypeXNWON = OpTypeXNWON { opKind :: FunKind, opArgsXNWON :: [XmlNamedWON SORT], opResXNWON :: (XmlNamedWON SORT) }
	deriving (Show, Eq, Ord)
	
sortToXmlNamedWONSORT::[XmlNamedWONSORT]->SORT->(Maybe XmlNamedWONSORT)
sortToXmlNamedWONSORT list s = find (\i -> s == (xnWOaToa i)) list

sortToXmlNamedWONSORTSet::Set.Set XmlNamedWONSORT->SORT->(Maybe XmlNamedWONSORT)
sortToXmlNamedWONSORTSet sortset sort =
	case Set.toList $ Set.filter (\i -> sort == (xnWOaToa i)) sortset of
		[] -> Nothing
		(i:_) -> (Just i)
		
aToXmlNamedWONa::(Eq a)=>[XmlNamedWON a]->a->(Maybe (XmlNamedWON a))
aToXmlNamedWONa xnlist a = find (\i -> a == (xnWOaToa i)) xnlist

aToXmlNamedWONaSet::(Eq a, Ord a)=>Set.Set (XmlNamedWON a)->a->(Maybe (XmlNamedWON a))
aToXmlNamedWONaSet xnset a =
	case Set.toList $ Set.filter (\i -> a == (xnWOaToa i)) xnset of
		[] -> Nothing
		(i:_) -> (Just i)
	
predTypeToPredTypeXNWON::Set.Set (XmlNamedWON SORT)->PredType->PredTypeXNWON
predTypeToPredTypeXNWON sortwoset (PredType {predArgs = pA}) =
	let
		xnwonsorts = Set.toList sortwoset
		xnwonargs = map (\a -> case (sortToXmlNamedWONSORT xnwonsorts a) of
			Nothing -> error "Unable to find xml-named sort for predicate argument!"
			(Just xnsort) -> xnsort) pA
	in
		PredTypeXNWON xnwonargs
		
predTypeXNWONToPredType::PredTypeXNWON->PredType
predTypeXNWONToPredType (PredTypeXNWON xnargs) =
	PredType $ map xnWOaToa xnargs
		
opTypeToOpTypeXNWON::Set.Set (XmlNamedWON SORT)->OpType->OpTypeXNWON
opTypeToOpTypeXNWON sortwoset (OpType {CASL.Sign.opKind = oK, opArgs = oA, opRes = oR}) =
	let
		xnwonsorts = Set.toList sortwoset
		xnwonargs = map (\a -> case (sortToXmlNamedWONSORT xnwonsorts a) of
			Nothing -> error "Unable to find xml-named sort for operator argument!"
			(Just xnsort) -> xnsort) oA
		xnwonres = case sortToXmlNamedWONSORT xnwonsorts oR of
			Nothing -> error "Unable to find xml-named sort for operator result!"
			(Just xnsort) -> xnsort
	in
		OpTypeXNWON oK xnwonargs xnwonres
		
opTypeXNWONToOpType::OpTypeXNWON->OpType
opTypeXNWONToOpType (OpTypeXNWON fk xnargs xnres) =
	OpType fk (map xnWOaToa xnargs) (xnWOaToa xnres)

-- unused ?
nodeNameInfo::NODE_NAME->HXT.XmlFilter
nodeNameInfo (tok, ext, int) =
	(HXT.etag "data" += (
		(HXT.sattr "format" "Hets-NodeName")
		+++ (HXT.sattr "pto" "Hets")
		+++ (HXT.cdata ((show tok) ++ "," ++ ext ++ "," ++ (show int)))
		))
				
-- | Convert a DevGraph to an XML-Representation (without omdoc parent)				
devGraphToXml::Static.DevGraph.DGraph->(HXT.XmlTree->HXT.XmlTrees)
devGraphToXml dg =
		let
			(onlynodenameset, onlyrefnameset) = Hets.getNodeNamesNodeRef dg
			nodenameset = Set.union onlynodenameset onlyrefnameset
			nodenamemap = Map.fromList $ Set.toList nodenameset
			--namenodemap = Map.fromList $ map (\(a,b) -> (b,a)) $ Map.toList nodenamemap
			--nodenames = Set.fromList $ map (\(_,a) -> a) $ Set.toList nodenameset
			sorts' = Hets.getSortsWithNodeNames dg
			rels' = Hets.getRelationsWithNodeNames dg
			preds' = Hets.getPredMapsWithNodeNames dg
			ops' = Hets.getOpMapsWithNodeNames dg
			sens = Hets.getSentencesWithNodeNames dg
			mimports = Hets.getNodeImportsNodeNames dg
			--imports' = Map.map (Set.map fst) mimports
		in
		    foldl (\dgx (node, name' ) ->
		    	let
					nSorts = fromMaybe Set.empty $ Map.lookup name' sorts' 
					-- OMDocS 'insort' is opposite to CASL-Sort-Relation 
					nInsorts = Rel.transpose $ fromMaybe Rel.empty $ Map.lookup name' rels'
					nInsortMap = foldl (\m (a,b) -> 
						Map.insert a (Set.insert b (Map.findWithDefault Set.empty a m)) m
						) Map.empty $ Rel.toList nInsorts
					nPreds = fromMaybe Map.empty $ Map.lookup name' preds'  
					nOps = fromMaybe Map.empty $ Map.lookup name' ops'
					nSens = fromMaybe Set.empty $ Map.lookup name' sens
					(_, sortgen) = partitionSensSortGen $ Set.toList nSens
					constructors = makeConstructors sortgen
					
					-- sort-imports (not all imports)
					nImports = fromMaybe Set.empty $ Map.lookup name' mimports
					-- what adts are needed (insort, cons or both)
					adtsorts = nub $ (map (\ (a,_) -> a) $ Map.toList nInsortMap) ++
						(map (\(a,_) -> a) $ Map.toList constructors)
					-- remove everything that came from a morphism
					(realSorts, realOps, realPreds) = foldl (\(rs, ro, rp) (_,mmm) ->
						case mmm of
							Nothing -> (rs, ro, rp)
							(Just mm) -> (Hets.removeMorphismSorts mm rs,
								Hets.removeMorphismOps mm ro,
								Hets.removeMorphismPreds mm rp)
							) (nSorts, nOps, nPreds) $ Set.toList nImports
				in
					dgx +++
					(HXT.etag "theory" += (qualattr theoryNameXMLNS theoryNameXMLAttr name' ))
					+= (
					   (foldl (\ix (i,mmm) -> ix +++ xmlNL +++ importToXml i +=
							(
							case mmm of
								Nothing -> HXT.txt ""
								(Just mm) ->
									morphismMapToXml mm i name' 
									+++
									xmlNL
							)
						) (HXT.txt "") $ Set.toList nImports)
					   +++
					   (foldl (\sx s -> sx +++ xmlNL +++ sortToXml s) (HXT.txt "") $ Set.toList realSorts) --nSorts)
					   +++
					   -- adt-generation needs some optimization...
					   (foldl (\adtx sort -> adtx +++ xmlNL
						+++ (
							let 
								sortrelation = (\a -> (sort, a)) $ Map.findWithDefault Set.empty sort nInsortMap
								cons = createAllConstructors $ Map.toList $ Map.findWithDefault Map.empty sort constructors
							in
								createADT sortrelation cons
							)
						) (HXT.txt "") adtsorts)
					   +++
					   (foldl (\px p -> px +++ xmlNL +++ predicationToXml mimports sorts' name' p)
						(HXT.txt "") $ Map.toList realPreds) --nPreds)
					   +++
					   (foldl (\px o' -> px +++ xmlNL +++ operatorToXml mimports sorts' name' o' )
						(HXT.txt "") $ Map.toList realOps) --nOps)
					   +++
					   (wrapFormulas mimports sorts' preds' ops' name' $ Set.toList nSens)
					   +++ xmlNL
					   )
					+++ xmlNL
					-- make private data for all incoming links
					+++ inDGToXml dg node nodenamemap 
					+++ xmlNL
				) (refsToCatalogue dg +++ xmlNL) $ Set.toList onlynodenameset
				
refsToCatalogue::DGraph->HXT.XmlFilter
refsToCatalogue dg =
	let refs = filter isDGRef $ map snd $ Graph.labNodes dg
	in
		HXT.etag "catalogue" += 
		(
		xmlNL +++
		foldl (\cx r ->
			cx +++
			HXT.etag "loc" +=
				( HXT.sattr "theory" (getDGNodeName r) +++ HXT.sattr "omdoc" (asOmdocFile (unwrapLinkSource $ dgn_libname r)) ) +++
				xmlNL
				) (HXT.txt "") refs
		)
		
refsToCatalogueXN::DGraph->TheoryXNSet->HXT.XmlFilter
refsToCatalogueXN dg theoryset =
	let
		refs = filter (\(_, node) -> isDGRef node) $ Graph.labNodes dg
	in
		HXT.etag "catalogue" += (
			xmlNL +++
			foldl (\cx (n, node) ->
				cx +++
				HXT.etag "loc" += (
					HXT.sattr
						"theory"
						(case getTheoryXmlName theoryset n of
							Nothing -> error "No Theory for Reference!"
							(Just xnname' ) -> xnname' )
						+++
					HXT.sattr "omdoc" (asOmdocFile (unwrapLinkSource $ dgn_libname node))
					) +++
					xmlNL
				) (HXT.txt "") refs
			)
		
-- | newline in XML
xmlNL::(HXT.XmlTree->HXT.XmlTrees)
xmlNL = HXT.txt "\n"

-- | create an imports-tag for a given source
importToXml::String->(HXT.XmlTree->HXT.XmlTrees)
importToXml i = HXT.etag "imports" += (HXT.sattr "from" ("#"++i))

-- | create a xml-representation for a SORT
sortToXml::SORT->(HXT.XmlTree->HXT.XmlTrees)
sortToXml s = HXT.etag "symbol" += (
	qualattr symbolTypeXMLNS symbolTypeXMLAttr "sort" +++
	qualattr sortNameXMLNS sortNameXMLAttr (show s)
	)

sortToXmlXN::XmlNamed SORT->HXT.XmlFilter
sortToXmlXN xnSort =
	((HXT.etag "symbol" +=
		( qualattr symbolTypeXMLNS symbolTypeXMLAttr "sort"
		+++ qualattr sortNameXMLNS sortNameXMLAttr (xnName xnSort)))
	{- +++ xmlNL +++
	(HXT.etag "presentation" += (
		(HXT.sattr "for" (xnName xnSort))
		+++ HXT.etag "use" += (
			(HXT.sattr "format" "Hets")
			+++ (HXT.txt (idToString (xnItem xnSort)))
			)
		)
	) -}
	)
	
-- | create an ADT for a SORT-Relation and constructor information (in xml)
createADT::(SORT, Set.Set SORT)->HXT.XmlFilter->HXT.XmlFilter
createADT (s,ss) constructors =
	HXT.etag "adt" -- += (qualattr "xml" "id" ((show s)++"-adt")) -- id must be unique but is optional anyway... 
	+= (
	    xmlNL +++
	    (HXT.etag "sortdef" += (
			HXT.sattr "name" (show s) +++
			HXT.sattr "type" "free" +++
			constructors +++
			(foldl (\isx is ->
				isx +++ xmlNL +++ (HXT.etag "insort" += (HXT.sattr "for" ("#"++(show is))))
			) (HXT.txt "") $ Set.toList ss)
			+++ xmlNL
			)
		)
	)

-- | create an ADT for a SORT-Relation and constructor information (in xml)
createADTXN::(XmlNamed SORT, Set.Set (XmlNamed SORT))->HXT.XmlFilter->HXT.XmlFilter
createADTXN (s,ss) constructors =
	HXT.etag "adt" -- += (qualattr "xml" "id" ((show s)++"-adt")) -- id must be unique but is optional anyway... 
	+= (
	    xmlNL +++
	    (HXT.etag "sortdef" += (
			HXT.sattr "name" (xnName s) +++
			HXT.sattr "type" "free" +++
			constructors +++
			(foldl (\isx is ->
				isx +++ xmlNL +++ (HXT.etag "insort" += (HXT.sattr "for" ("#" ++ (xnName is))))
			) (HXT.txt "") $ Set.toList ss)
			+++ xmlNL
			) +++ xmlNL
		)
	)
	
-- | creates a xml-representation for a list of constructors	
createAllConstructors::[(Id.Id, Set.Set OpType)]->HXT.XmlFilter
createAllConstructors cs = foldl (\cx c ->
	cx +++ createConstructors c +++ xmlNL ) (HXT.txt "") cs 
	
-- | creates a xml-representation for all types of a constructor
createConstructors::(Id.Id, Set.Set OpType)->HXT.XmlFilter
createConstructors (cid, opset) = foldl (\cx op -> cx +++ createConstructor cid op +++ xmlNL) (HXT.txt "") $ Set.toList opset
	
-- | create a xml-representation for one type of a constructor
createConstructor::Id.Id->OpType->HXT.XmlFilter
createConstructor cid (OpType _ args _) =
	HXT.etag "constructor" += (
		HXT.sattr "name" (show cid) +++
		xmlNL +++
		foldl (\argx arg ->
			argx +++ xmlNL +++
			(HXT.etag "argument" += (HXT.sattr "sort" (show arg)))
			) (HXT.txt "") args
		)
		
createAllConstructorsXN::TheoryXNSet->[(XmlNamedWON Id.Id, Set.Set OpTypeXNWON)]->HXT.XmlFilter
createAllConstructorsXN theoryset cs = foldl (\cx c ->	
	cx +++ createConstructorsXN theoryset c +++ xmlNL ) (HXT.txt "") cs
		
createConstructorsXN::TheoryXNSet->(XmlNamedWON Id.Id, Set.Set OpTypeXNWON)->HXT.XmlFilter
createConstructorsXN theoryset (cidxn, opxnset) = foldl (\cx opxn -> cx +++ createConstructorXN theoryset cidxn opxn +++ xmlNL) (HXT.txt "") $ Set.toList opxnset
		
createConstructorXN::TheoryXNSet->(XmlNamedWON Id.Id)->OpTypeXNWON->HXT.XmlFilter
createConstructorXN theoryset cidxn (OpTypeXNWON _ opargsxn _) =
	HXT.etag "constructor" += (
		HXT.sattr "name" (xnName cidxn) +++
		xmlNL +++
		foldl (\argx arg ->
			argx +++ xmlNL +++
			--(HXT.etag "argument" += (HXT.sattr "sort" (xnName arg))) -- old syntax ?
			(HXT.etag "argument" += (
				HXT.etag "type" += (
					HXT.etag "OMOBJ" += (
						HXT.etag "OMS" += (
							HXT.sattr
								"cd"
								(case getTheoryXmlName theoryset (xnWOaToO arg) of
									Nothing -> "unknown"
									(Just xnname' ) -> xnname'
								)
							+++
							HXT.sattr "name" (xnName arg)
							)
						)
					)
				)
			)
			) (HXT.txt "") opargsxn
		)
		
initOrEmpty::[a]->[a]
initOrEmpty [] = []
initOrEmpty l = init l

extractConsFromADT::HXT.XmlTrees->(Id.Id, [(Id.Id, OpType)])
extractConsFromADT t =
	let
		--sort = Hets.stringToId $ reverse $ drop (length "-adt") $ reverse $
		--		xshow $ applyXmlFilter (isTag "adt" .> getQualValue "xml" "id") t
		sort = Hets.stringToId $ xshow $ applyXmlFilter (isTag "adt" .> getChildren
			.> isTag "sortdef" .> getValue "name") t
		cons = applyXmlFilter (getChildren .> isTag "sortdef" .> getChildren .> isTag "constructor") t
	in
		(sort, map (\n -> extractCon [n] sort) cons)
		
	where
		extractCon::HXT.XmlTrees->Id.Id->(Id.Id, OpType) -- empty list on error
		extractCon t' sort =
			let
				name' = xshow $ applyXmlFilter (getValue "name") t'
				args = map (\n -> Hets.stringToId $ xshow [n]) $ applyXmlFilter (getChildren .> isTag "argument" .> getValue "sort") t'
			in
				(Hets.stringToId name' , OpType Total args sort)
				
consToSens::Id.Id->[(Id.Id, OpType)]->(Ann.Named CASLFORMULA)
consToSens sort conlist =
	Ann.NamedSen
		("ga_generated_" ++ show sort)
		True
		False
		(Sort_gen_ax
			(
			foldl (\constraints (id' , ot) ->
				constraints ++
				[ Constraint
					sort
					[(Qual_op_name id' (cv_OpTypeToOp_type ot) Id.nullRange , [0])] 
					sort
				]
				) [] conlist
			)
			True
		)
		
-- | creates a xml-representation for a predication
-- needs a map of imports, sorts, the name of the current theory and the predication
predicationToXml::Hets.ImportsMap->Hets.SortsMap->String->(Id.Id, (Set.Set PredType))->(HXT.XmlTree->HXT.XmlTrees)
predicationToXml imports' sorts' name' (predId, ptSet) =
	(HXT.etag "symbol" += (
		qualattr predNameXMLNS predNameXMLAttr (show predId)
		+++ qualattr symbolTypeXMLNS symbolTypeXMLAttr "object"
		)
	) += ( 
		foldl (\tx (PredType predArgs' ) ->
			tx +++ xmlNL
			+++
			(HXT.etag "type" += (
				HXT.sattr "system" "casl"
				)
			) += (
				xmlNL +++
				HXT.etag "OMOBJ" += (
					xmlNL +++
					HXT.etag "OMA" += (
						xmlNL +++
						(HXT.etag "OMS" += (
							HXT.sattr "cd" "casl"
							+++ HXT.sattr "name" "predication"
							)
						) +++
						(foldl (\px s ->
							px +++ xmlNL
							+++
							(HXT.etag "OMS" += (
								HXT.sattr
									"cd"
									(fromMaybe
										"unknownOrigin"
										(Hets.findNodeNameForSort
											imports'
											sorts'
											s
											name' )
									)
									+++ HXT.sattr "name" (show s)
								)
							)
						) (HXT.txt "") predArgs' )
						+++ xmlNL
					)
					+++ xmlNL
				)
				+++ xmlNL
			)
			+++ xmlNL
		) (HXT.txt "") $ Set.toList ptSet
	)
	
type TheoryXN = XmlNamed (Graph.Node, NODE_NAME)
	
type TheoryXNSet = Set.Set TheoryXN
	
getTheoryXmlName::TheoryXNSet->Graph.Node->Maybe XmlName
getTheoryXmlName ts n =
	case find (\i -> (fst (xnItem i)) == n) $ Set.toList ts of
		Nothing -> Nothing
		(Just i) -> Just (xnName i)
		
getNodeForTheoryName::TheoryXNSet->XmlName->Maybe Graph.Node
getNodeForTheoryName xntheoryset xname =
	case find (\i -> (xnName i) == xname) $ Set.toList xntheoryset of
		Nothing -> Nothing
		(Just i) -> Just (fst (xnItem i))
		
-- | creates a xml-representation for a predication
-- needs a map of imports, sorts, the name of the current theory and the predication
predicationToXmlXN::TheoryXNSet->(XmlNamedWON Id.Id, PredTypeXNWON)->(HXT.XmlTree->HXT.XmlTrees)
predicationToXmlXN theoryset (pIdXN, (PredTypeXNWON predArgsXN)) =
	(HXT.etag "symbol" += (
		qualattr predNameXMLNS predNameXMLAttr (xnName pIdXN)
		+++ qualattr symbolTypeXMLNS symbolTypeXMLAttr "object"
		)
	) += ( 
			xmlNL
			+++
			(HXT.etag "type" += (
				HXT.sattr "system" "casl"
				)
			) += (
				xmlNL +++
				HXT.etag "OMOBJ" += (
					xmlNL +++
					HXT.etag "OMA" += (
						xmlNL +++
						(HXT.etag "OMS" += (
							HXT.sattr "cd" "casl"
							+++ HXT.sattr "name" "predication"
							)
						) +++
						(foldl (\px sxn ->
							px +++ xmlNL
							+++
							(HXT.etag "OMS" += (
								HXT.sattr
									"cd"
									(fromMaybe
										"unknownOrigin"
										(getTheoryXmlName theoryset (xnWOaToO sxn))
									)
									+++ HXT.sattr "name" (xnName sxn)
								)
							)
						) (HXT.txt "") predArgsXN )
						+++ xmlNL
					)
					+++ xmlNL
				)
				+++ xmlNL
			)
			+++ xmlNL
		)
	
-- | creates a xml-representation for an operator
-- needs a map of imports, sorts, the name of the current theory and the operator
operatorToXml::Hets.ImportsMap->Hets.SortsMap->String->(Id.Id, (Set.Set OpType))->(HXT.XmlTree->HXT.XmlTrees)
operatorToXml imports' sorts' name' (opId, otSet) =
-- NAME -> ID
	(HXT.etag "symbol" += (qualattr opNameXMLNS opNameXMLAttr (show opId) +++ qualattr symbolTypeXMLNS symbolTypeXMLAttr "object"))
	+= ( 
		foldl (\tx (OpType fk opArgs' opRes' ) ->
		tx +++ xmlNL
		+++
		(HXT.etag "type" += (HXT.sattr "system" "casl"))
		+= (	xmlNL +++
			HXT.etag "OMOBJ"
			+= (
				xmlNL +++
				HXT.etag "OMA"
				+= (
					xmlNL +++
					(HXT.etag "OMS" += (HXT.sattr "cd" "casl" +++ HXT.sattr "name" (if fk==Total then "function" else "partial-function") ))
					+++
					(foldl (\px s ->
						px +++ xmlNL
						+++
						createSymbolForSort imports' sorts' s name'
						) (HXT.txt "") opArgs' )
					+++ xmlNL +++
					createSymbolForSort imports' sorts' opRes' name'
					+++ xmlNL
				)
				+++ xmlNL
			)
			+++ xmlNL
		)
		+++ xmlNL
		) (HXT.txt "") $ Set.toList otSet
	)
	
-- | creates a xml-representation for an operator
-- needs a map of imports, sorts, the name of the current theory and the operator
operatorToXmlXN::TheoryXNSet->(XmlNamedWON Id.Id, OpTypeXNWON)->(HXT.XmlTree->HXT.XmlTrees)
operatorToXmlXN theoryset (opIdXN, (OpTypeXNWON fk opArgsXN opResXN)) =
-- NAME -> ID
	(HXT.etag "symbol" += (
		qualattr opNameXMLNS opNameXMLAttr (xnName opIdXN)
		+++ qualattr symbolTypeXMLNS symbolTypeXMLAttr "object")
	)
	+= ( 
		xmlNL
		+++
		(HXT.etag "type" += (HXT.sattr "system" "casl"))
		+= (	xmlNL +++
			HXT.etag "OMOBJ"
			+= (
				xmlNL +++
				HXT.etag "OMA"
				+= (
					xmlNL +++
					(HXT.etag "OMS" += (HXT.sattr "cd" "casl" +++ HXT.sattr "name" (if fk==Total then "function" else "partial-function") ))
					+++
					(foldl (\px sxn ->
						px +++ xmlNL
						+++
						createSymbolForSortXN theoryset sxn
						) (HXT.txt "") opArgsXN )
					+++ xmlNL +++
					createSymbolForSortXN theoryset opResXN
					+++ xmlNL
				)
				+++ xmlNL
			)
			+++ xmlNL
		)
		+++ xmlNL
	)
	
sortToOM::Hets.ImportsMap->Hets.SortsMap->String->SORT->HXT.XmlFilter
sortToOM imports' sorts' name' s =
	HXT.etag "OMS" +=
		(
		HXT.sattr "cd" (fromMaybe "unknown" $ Hets.findNodeNameForSort imports' sorts' s name' ) +++
		HXT.sattr "name" (show s)
		)
		
opToOM::Hets.ImportsMap->Hets.OpsMap->String->Id.Id->HXT.XmlFilter
opToOM imports' ops' name' id' =
	HXT.etag "OMS" +=
		(
		HXT.sattr "cd" (fromMaybe "unknown" $ Hets.findNodeNameForOperator imports' ops' id' name' ) +++
		HXT.sattr "name" (show id' )
		)
	
inOMOBJ::HXT.XmlFilter->(HXT.XmlTree->HXT.XmlTrees)
inOMOBJ x = HXT.etag "OMOBJ" += x

transformMorphOp::(Id.Id, OpType)->OP_SYMB
transformMorphOp (id' , ot) = Qual_op_name id' (cv_OpTypeToOp_type ot) Id.nullRange

transformMorphPred::(Id.Id, PredType)->PRED_SYMB
transformMorphPred (id' , pt) = Qual_pred_name id' (cv_PredTypeToPred_type pt) Id.nullRange

createHidingString2::(Hets.Sorts, Hets.Rels, Hets.Preds, Hets.Ops)->String
createHidingString2 (sorts' , _ , preds' , ops' ) =
	let	hidden = map show (Set.toList sorts' ) ++
			map show (Map.keys preds' ) ++
			map show (Map.keys ops' )
	in implode ", " hidden
	
morphismMapToXml::Hets.MorphismMap->String->String->HXT.XmlFilter
morphismMapToXml (sm, om, pm, hs) source target =
	HXT.etag "morphism" +=
		(
		(HXT.sattr "hiding" (implode ", " $ map show $ Set.toList hs))
		+++
		(foldl (\sx (ss,st) ->
			sx +++
			requation
				(inOMOBJ
					(
					HXT.etag "OMS" += (HXT.sattr "cd" source +++ HXT.sattr "name" (show ss))
					))
				(inOMOBJ
					(
					HXT.etag "OMS" += (HXT.sattr "cd" target +++ HXT.sattr "name" (show st))
					))
		) (HXT.txt "") $ Map.toList sm)
		+++
		(foldl (\sx ((sid, sot),(tid, tot)) ->
			sx +++
			requation
				(inOMOBJ (processOperatorForMorphism sid sot source))
				(inOMOBJ (processOperatorForMorphism tid tot target))
		) (HXT.txt "") $ Map.toList om)
		+++
		(foldl (\sx ((sid, spt),(tid, tpt)) ->
			sx +++
			requation
				(inOMOBJ (processPredicationForMorphism sid spt source))
				(inOMOBJ (processPredicationForMorphism tid tpt target))
		) (HXT.txt "") $ Map.toList pm)
		)
	where
	requation::(HXT.XmlTree->HXT.XmlTrees)->(HXT.XmlTree->HXT.XmlTrees)->(HXT.XmlTree->HXT.XmlTrees)
	requation p v =
		HXT.etag "requation" +=
			(
			xmlNL +++
			p +++
			xmlNL +++
			v +++
			xmlNL
			) +++
		xmlNL
		
processOperatorForMorphism::Id.Id->OpType->String->HXT.XmlFilter
processOperatorForMorphism 
	opid (OpType fk args res) source =
		HXT.etag "OMATTR" +=
			(xmlNL +++
			HXT.etag "OMATP" += -- create attribution for this operator (sign)
				(xmlNL +++
				HXT.etag "OMS" += -- type of operator
					(HXT.sattr "cd" "casl" +++
					HXT.sattr "name" "funtype"
					) +++
				xmlNL +++
				(HXT.etag "OMSTR" +=
					(HXT.txt (show fk)) -- 'Partial' or 'Total'
				) +++
				xmlNL +++
				HXT.etag "OMS" += -- signature of operator
					(HXT.sattr "cd" "casl" +++
					HXT.sattr "name" "type"
					) +++
				xmlNL +++
				(HXT.etag "OMSTR" += -- create a string t1-\\t2-\\...-\\tn
					(HXT.txt ( (foldl
						(\t s -> t ++ (show s) ++ "-\\")
						-- the function could be easier but we need different
						-- behaviour for functions without parameters...
						(if (length args > 0) then
								(show (head args)) ++ "-\\"
							else
								"" )
						(if (length args) > 0 then tail args else [])
						) ++ (show res) )
					)
				) +++
				xmlNL
				) +++
				xmlNL +++
				HXT.etag "OMS" += -- finally : the name of the operator
					(
					HXT.sattr "cd" source
					+++
					HXT.sattr "name" (show opid)
					)
			)
			
processPredicationForMorphism::Id.Id->PredType->String->HXT.XmlFilter
processPredicationForMorphism
	prid (PredType args) source =
		HXT.etag "OMATTR" +=
			(xmlNL +++
			HXT.etag "OMATP" +=
				(xmlNL +++
				HXT.etag "OMS" +=
					(HXT.sattr "cd" "casl" +++ HXT.sattr "name" "type") +++
				xmlNL +++
				(HXT.etag "OMSTR" +=
					HXT.txt
						( (foldl
							(\t s -> t ++ "-\\" ++ (show s))
							(if args == [] then "" else (show $ head args))
							(drop 1 args)
						   )
						)
				)
				) +++
				xmlNL
			) +++
		xmlNL +++
		HXT.etag "OMS" +=
			(
			 HXT.sattr "cd" source
			 +++
			 HXT.sattr "name" (show prid)
			) 

		


caslMorphismToXml::Hets.ImportsMap->Hets.SortsMap->Hets.PredsMap->Hets.OpsMap->String->String->(CASL.Morphism.Morphism () () ())->HXT.XmlFilter
caslMorphismToXml imports' sorts' preds' ops' sourcename targetname (CASL.Morphism.Morphism ssource starget sortmap funmap predmap _) =
	let
		hides = Hets.createHidingString $ diffSig ssource starget
{-		hides = createHidingString2 $ (\(a,b,c,d,_) -> (a,b,c,d)) $
			Hets.diffMaps
				(Hets.lookupMaps sorts Map.empty preds ops Map.empty sourcename)
				(Hets.lookupMaps sorts Map.empty preds ops Map.empty targetname) -}
		morphx =
			HXT.etag "morphism" +=
				(
				(if (length hides) /= 0 then
					HXT.sattr "hiding" hides
				else
					HXT.txt "") +++
				(foldl (\mx (ss,st) ->
					mx +++
					HXT.etag "requation" +=
						(
						xmlNL +++
						HXT.etag "pattern" +=
							(
							xmlNL +++
							(inOMOBJ $ sortToOM imports' sorts' sourcename ss)
							)
						 +++
						HXT.etag "value" +=
							(
							xmlNL +++
							(inOMOBJ $ sortToOM imports' sorts' targetname st)
							)
						)
					+++ xmlNL
					) (xmlNL) $ Map.toList sortmap)
				+++ 
				(foldl (\mx ((ids, ots), (idt, fkt)) ->
					mx +++
					HXT.etag "requation" +=
						(
						xmlNL +++
						HXT.etag "pattern" +=
							(
							xmlNL +++
							(inOMOBJ $
								(processOperator
									imports'
									ops'
									sourcename
		-- using a qualified OP_SYMB does not work correctly.
		-- for example the reference to Sample/Simple in 
		-- Advancend/Architectural has a morphism with a
		-- Partial Operator while the Operator is defined as Total...
		--							(transformMorphOp
		--								(ids, ots)
		-- workaround :
		-- try both variants for function kind...
								(
									let	op = transformMorphOp (ids, ots)
										-- get cd for original optype
										cd = Hets.findNodeNameForOperatorWithSorts
												imports'
												ops'
												(ids, ots)
												sourcename
										-- optype with flipped function kind
										ots' = (\(OpType fk args res) ->
											OpType 
												(case fk of
													Partial -> Total
													Total -> Partial)
												args
												res ) ots
										-- operator with flipped fk
										op' = transformMorphOp (ids, ots' )
										-- get cd for 'flipped' optype
										cd' = Hets.findNodeNameForOperatorWithSorts
												imports'
												ops'
												(ids, ots' )
												sourcename
										-- check if a cd was found for the original op
										-- if not, check if there was one for the flipped
										-- if this fails use the original op again
										-- (in this case something else is wrong...)
										op'' = if cd == Nothing then
													if cd' == Nothing then
														op
													else
														op'
												else
													op
									-- actually this leads into generating output that
									-- in turn will lead to an input with this morphism
									-- wich may be different to the intended morphism...
									in op''
								)
		
								)
								
							) +++
							xmlNL
							)
						+++
						xmlNL +++
						HXT.etag "value" +=
							( xmlNL +++
							( let	otset = Set.filter (\(OpType fk _ _) -> fk == fkt) $
										Map.findWithDefault Set.empty idt $
											Map.findWithDefault Map.empty targetname ops'
								ott = if Set.null otset
									then
										error "Cannot find Operator for Morphism..."
									else
										head $ Set.toList otset
							  in 
								inOMOBJ $
									processOperator
										imports'
										ops'
										targetname
										(transformMorphOp
											(idt, ott)
										)
							) +++
							xmlNL
						) +++
						xmlNL
						)
					+++ xmlNL
					) (HXT.txt "") $ Map.toList funmap)
				+++ 
				(foldl (\mx ((ids, pts), idt) ->
					mx +++
					HXT.etag "requation" +=
						(
						HXT.etag "pattern" +=
							( inOMOBJ $
								createSymbolForPredication imports' preds' sourcename
									(transformMorphPred (ids, pts))
							) +++
						HXT.etag "value" +=
							( let	ptset = Map.findWithDefault Set.empty idt $
										Map.findWithDefault Map.empty targetname preds'
							
								ptt = if Set.null ptset
										then
											error "Cannot find Predication for Morphism..."
										else
											head $ Set.toList ptset
							  in
								inOMOBJ $
									createSymbolForPredication imports' preds' targetname
										(transformMorphPred (idt, ptt))
							) +++
						xmlNL
						)
					+++ xmlNL
					) (HXT.txt "") $ Map.toList predmap)
				)
			in
				morphx -- maybe some postprocessing ?
	

processXmlMorphism::
	Hets.ImportsMap->
	Hets.SortsMap->
	Hets.PredsMap->
	Hets.OpsMap->
	String->
	String->
	HXT.XmlTrees->
	(
		Hets.ImportsMap,
		Hets.SortsMap,
		Hets.PredsMap,
		Hets.OpsMap,
		(Morphism () () ())
	)
processXmlMorphism
	imports'
	sorts'
	preds'
	_ -- ops'
	_ -- sourcename
	targetname
	t
	=
		let
			--sourcesorts = Map.findWithDefault Set.empty sourcename sorts'
			--targetsorts = Map.findWithDefault Set.empty targetname sorts'
			--hides = xshow $ applyXmlFilter (isTag "morphism" .> getQualValue "" "hiding") t
			pattern = isTag "requation" .> getChildren .> isTag "pattern"
			value = isTag "requation" .> getChildren .> isTag "value"
			vsymbol = value .> getChildren .> isTag "OMOBJ" .> getChildren .> isTag "OMS" .> getQualValue "" "name" 
			requations = applyXmlFilter (isTag "morphism" .> getChildren .> isTag "requation") t
			newSymbolsSet = foldl (\ns ts ->
				case applyXmlFilter (value .> getChildren .> isTag "OMATTR") [ts] of
					[] ->	let
								symbolname = xshow $ applyXmlFilter vsymbol [ts]
							in
								if symbolname /= [] then
									Set.union ns (Set.singleton (Hets.stringToId $ symbolname))
									else
									ns
					_ -> ns
					) Set.empty requations
			newOpsMap = foldl (\np tp ->
				case xshow $ applyXmlFilter (
					pattern .> getChildren .> 
					isTag "OMOBJ" .> getChildren .>
					isTag "OMATTR" .> getChildren .>
					isTag "OMATP" .> getChildren .>
					isTag "OMS" .> withSValue "cd" "casl" .> withSValue "name" "funtype" .> getQualValue "" "name") [tp] of
					"funtype" ->
					{-	let	satp = applyXmlFilter (
								pattern .> getChildren .>
								isTag "OMOBJ" .> getChildren .>
								isTag "OMATTR" .> getChildren .>
								isTag "OMATP") [tp]
							tatp = applyXmlFilter (
								value .> getChildren .>
								isTag "OMOBJ" .> getChildren .>
								isTag "OMATTR" .> getChildren .>
								isTag "OMATP") [tp]
							satpsym = applyXmlFilter (getChildren .> isTag "OMS") satp
							satpstr = applyXmlFilter (getChildren .> isTag "OMSTR") satp
							satpmap = Map.fromList $ zip
								(map (\t -> xshow $ applyXmlFilter (getQualValue "" "name") [t]) satpsym)
								(map (\t -> xshow $ applyXmlFilter (getChildren) [t]) satpstr) 
							tatpsym = applyXmlFilter (getChildren .> isTag "OMS") tatp
							tatpstr = applyXmlFilter (getChildren .> isTag "OMSTR") tatp
							tatpmap = Map.fromList $ zip
								(map (\t -> xshow $ applyXmlFilter (getQualValue "" "name") [t]) tatpsym)
								(map (\t -> xshow $ applyXmlFilter (getChildren) [t]) tatpstr)
							 ssymbolname = xshow $ applyXmlFilter (
								pattern .> getChildren .>
								isTag "OMOBJ" .> getChildren .>
								isTag "OMATTR" .> getChildren .> 
								isTag "OMS" .> getValue "name" ) [tp]
							tsymbolname = xshow $ applyXmlFilter (
								value .> getChildren .>
								isTag "OMOBJ" .> getChildren .>
								isTag "OMATTR" .> getChildren .> 
								isTag "OMS" .> getValue "name" ) [tp] 
							 sorts'' = explode "-\\" $ Map.findWithDefault "" "type" tatpmap
							 newOp = Op_type
								(funKindFromName $ Map.findWithDefault "Total" "funtype" tatpmap)
								(map Hets.stringToId ( if (length sorts'' ) == 1 then [] else init sorts'' ))
								(Hets.stringToId $ last sorts'' ) Id.nullRange
						in -}
							np
					x -> Debug.Trace.trace x np
					) Map.empty requations
		in
			(imports' , (Map.adjust (Set.union (Debug.Trace.trace ("new symbol set : "++(show newSymbolsSet)) newSymbolsSet)) targetname sorts' ), preds' , newOpsMap, Hets.emptyCASLMorphism)

singleitem::Int->[a]->[a]
singleitem _ [] = []
singleitem 0 _ = []
singleitem 1 (i:_) = [i]
singleitem n (_:r) = singleitem (n-1) r

getChild::Int->XmlFilter
getChild c (NTree _ cs) = singleitem c cs

xmlToMorphismMap::
	HXT.XmlTrees->
	Hets.MorphismMap
xmlToMorphismMap
	t
	=
		let
			hides = xshow $ applyXmlFilter (isTag "morphism" .> getQualValue "" "hiding") t
			hiddensyms = map Hets.stringToId $ map trimString $ explode "," hides
			pattern = isTag "requation" .> processChildren (isTag "OMOBJ") .> getChild 1
			value = isTag "requation" .> processChildren (isTag "OMOBJ") .> getChild 2
			vsymbol = value .> getChildren .> isTag "OMS" .> getQualValue "" "name" 
			psymbol = pattern .> getChildren .> isTag "OMS" .> getQualValue "" "name" 
			requations = applyXmlFilter (isTag "morphism" .> getChildren .> isTag "requation") t
			sortmap = foldl (\sm ts ->
				case applyXmlFilter (value .> getChildren .> isTag "OMATTR") [ts] of
					[] ->	let
								psymbolname = xshow $ applyXmlFilter psymbol [ts]
								vsymbolname = xshow $ applyXmlFilter vsymbol [ts]
							in
								if (psymbolname /= []) && (vsymbolname /= []) then
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
					tOp = OpType
						(funKindFromName $ Map.findWithDefault "Total" "funtype" tatpmap)
						(map Hets.stringToId ( if (length tsorts) == 1 then [] else init tsorts ))
						(Hets.stringToId $ last tsorts)
					tPred = PredType
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
								(Map.insert (Hets.stringToId ssymbolname, sOp) (Hets.stringToId tsymbolname, tOp) om, pm)
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

			
--helper
getAll::DGraph->(Hets.ImportsMap, Hets.SortsMap, Hets.RelsMap, Hets.PredsMap, Hets.OpsMap, Hets.SensMap)
getAll dg =
	(
		Hets.getNodeImportsNodeNames dg,
		Hets.getSortsWithNodeNames dg,
		Hets.getRelationsWithNodeNames dg,
		Hets.getPredMapsWithNodeNames dg,
		Hets.getOpMapsWithNodeNames dg,
		Hets.getSentencesWithNodeNames dg
	)
			
-- | this function partitions a list of CASLFORMULAS into two lists of
-- 'CASLFORMULA's : the first list contains 'normal' CFs and the second
-- all CFs that generate sorts (constructors)
partitionSensSortGen::[Ann.Named CASLFORMULA]->([Ann.Named CASLFORMULA],[Ann.Named CASLFORMULA])
partitionSensSortGen sens =
	foldl (\(sens' ,sortgen) s@(Ann.NamedSen name' _ _ sentence) ->
		if isPrefixOf "ga_generated_" name' then
			case sentence of
				(Sort_gen_ax _ True) -> (sens' , sortgen++[s])
				_ -> (sens' ++[s],sortgen)
		else
			(sens' ++[s],sortgen)
		) ([],[]) sens

-- | this function partitions a list of CASLFORMULAS into two lists of
-- 'CASLFORMULA's : the first list contains 'normal' CFs and the second
-- all CFs that generate sorts (constructors)
partitionSensSortGenXN::[XmlNamedWON (Ann.Named CASLFORMULA)]->([XmlNamedWON (Ann.Named CASLFORMULA)], [XmlNamedWON (Ann.Named CASLFORMULA)])
partitionSensSortGenXN sens =
	foldl (\(sens' ,sortgen) xnsens -> --s@(Ann.NamedSen name' _ _ sentence) ->
		let
			(Ann.NamedSen name' _ _ sentence) = xnWOaToa xnsens
		in
			if isPrefixOf "ga_generated_" name' then
				case sentence of
					(Sort_gen_ax _ True) -> (sens' , sortgen++[xnsens])
					_ -> (sens' ++ [xnsens],sortgen)
			else
				(sens' ++[xnsens],sortgen)
		) ([],[]) sens

-- | creates constructors from a list of 'CASLFORMULA's (see : 'partitionSensSortGen')
makeConstructors::[Ann.Named CASLFORMULA]->(Map.Map Id.Id (Map.Map Id.Id (Set.Set OpType)))
makeConstructors sortgenaxlist =
	Map.fromList $ map makeConstructorMap sortgenaxlist
	
makeConstructorsXN::Set.Set XmlNamedWONSORT->XmlNameList->[XmlNamedWON (Ann.Named CASLFORMULA)]->(Map.Map (XmlNamedWON Id.Id) (Map.Map (XmlNamedWON Id.Id) (Set.Set OpTypeXNWON)), XmlNameList)
makeConstructorsXN sortxnwoset xmlnames sortgenaxxnlist =
	foldl (\(mapping, xmlnames' ) sortgenaxxn ->
		let
			(conidxnwo, conmap, xmlnames'' ) =
				makeConstructorMapXN sortxnwoset xmlnames' sortgenaxxn
		in
			(Map.insertWith (\a b -> Map.union a b) conidxnwo conmap mapping, xmlnames'' )
			) (Map.empty, xmlnames) sortgenaxxnlist
					
		
--	Map.fromList $ map makeConstructorMapXN sortgenaxxnlist

-- | creates constructors from a 'CASLFORMULA'
makeConstructorMap::(Ann.Named CASLFORMULA)->(Id.Id, (Map.Map Id.Id (Set.Set OpType)))
makeConstructorMap (Ann.NamedSen senname _ _ (Sort_gen_ax cons _)) =
	let	sort = drop (length "ga_generated_") senname
		constructormap = foldl(\cmap (Constraint _ symbs _) ->
			foldl(\tcmap (Qual_op_name name' ot _) ->
				Map.insertWith (Set.union) name' (Set.singleton (cv_Op_typeToOpType ot)) tcmap) cmap $ map fst symbs
				) Map.empty cons
	in (Hets.stringToId sort, constructormap)
makeConstructorMap _ = error "Wrong application of makeConstructorMap!"

makeConstructorMapXN::Set.Set XmlNamedWONSORT->XmlNameList->XmlNamedWON (Ann.Named CASLFORMULA)->(XmlNamedWON Id.Id, (Map.Map (XmlNamedWON Id.Id) (Set.Set OpTypeXNWON)), XmlNameList)
makeConstructorMapXN sortxnwoset xmlnames sensxnwo =
	let
		sens = xnWOaToa sensxnwo
		(Ann.NamedSen senname _ _ (Sort_gen_ax cons _)) = sens
		origin = xnWOaToO sensxnwo
		sort = drop (length "ga_generated_") senname
		sortxn = case sortToXmlNamedWONSORT (Set.toList sortxnwoset) (Hets.stringToId sort) of
			Nothing -> error "Cannot find sort to make constructor for!"
			(Just sortxn' ) -> sortxn'
		(constructormap, xmlnames' ) =
			foldl(\(cmap, xmlnames'' ) (Constraint _ symbs _) ->
				foldl (\(tcmap, xmlnames''' ) (Qual_op_name name' ot _) ->
					let
						opxmlname = createUniqueName xmlnames''' (adjustStringForXmlName (show name' ))
					in
						(Map.insertWith (Set.union) (XmlNamed (Hets.mkWON name' origin) opxmlname) (Set.singleton (opTypeToOpTypeXNWON sortxnwoset (cv_Op_typeToOpType ot))) tcmap, xmlnames''' )
					) (cmap, xmlnames'' ) $ map fst symbs
				) (Map.empty, xmlnames) cons
	in
		(sortxn, constructormap, xmlnames' )
		

-- | creates a String-representation of a DGLinkType	
linkTypeToString::DGLinkType->String
linkTypeToString LocalDef = "LocalDef"
linkTypeToString GlobalDef = "GlobalDef"
linkTypeToString HidingDef = "HidingDef"
linkTypeToString (LocalThm _ cons _) = "LocalThm Open "++ conservativityToString cons ++ " Open"
linkTypeToString (GlobalThm _ cons _) = "GlobalThm Open "++ conservativityToString cons ++ " Open"
linkTypeToString (HidingThm _ _) = "HidingThm EmptyMorphism Open"
linkTypeToString (FreeDef _) = "FreeDef EmptyNode"
linkTypeToString (CofreeDef _) = "CofreeDef EmptyNode"
-- TODO
-- Parameters 
linkTypeToString x = (take 7 (show x)) ++ "..."

-- | creates a String-representation of a Conservativity
conservativityToString::Conservativity->String
conservativityToString None = "None"
conservativityToString Cons = "Cons"
conservativityToString Mono = "Mono"
conservativityToString Def = "Def"

-- | creates a Conservativity from a String or fails with error
stringToConservativity::String->Conservativity
stringToConservativity "None" = None
stringToConservativity "Cons" = Cons
stringToConservativity "Mono" = Mono
stringToConservativity "Def" = Def
stringToConservativity s = error ("Unknown Conservativity : \"" ++ s ++ "\"") 

-- | creates a String-representation of a DGLinkLab
linkToString::DGLinkLab->String
linkToString dgl =
	"Type:\"" ++ (linkTypeToString $ dgl_type dgl) ++ "\" Origin:\"" ++ (show $ dgl_origin dgl) ++ "\""

-- | stringToLinkType returns a list with at most one DGLinkType
-- Unknown links result in empty list
-- Currently this does not work very well because of some formatting issues...
stringToLinkType::String->[DGLinkType]
stringToLinkType s =
	if (length $ words s) == 0 then [] -- error "Cannot determine DGLinkType from empty string!"
	else
	let firstword = (words s)!!0
	in
	case firstword of
		"LocalDef" -> [LocalDef]
		"GlobalDef" -> [GlobalDef]
		"HidingDef" -> [HidingDef]
		"LocalThm" ->
			if (length $ words s) < 3 then Debug.Trace.trace ("No data for Conservativity in \"" ++ s ++ "\"") []
			else
			[LocalThm LeftOpen (stringToConservativity $ (words s)!!2) LeftOpen] 
		"GlobalThm" ->
			if (length $ words s) < 3 then Debug.Trace.trace ("No data for Conservativity in \"" ++ s ++ "\"") []
			else
			[GlobalThm LeftOpen (stringToConservativity $ (words s)!!2) LeftOpen]
		"HidingThm" ->
			[HidingThm Hets.emptyCASLGMorphism LeftOpen]
		"FreeDef" ->
			[FreeDef (EmptyNode (Logic.Logic CASL))]
		"CofreeDef" ->
			[CofreeDef (EmptyNode (Logic.Logic CASL))]
		_ -> Debug.Trace.trace ("Unknown DGLinkType : \"" ++ firstword ++ "\"") []
		
defaultDGLinkType::DGLinkType
defaultDGLinkType = GlobalDef

defaultDGOrigin::DGOrigin
defaultDGOrigin = DGExtension

defaultDGLinkLab::DGLinkLab
defaultDGLinkLab = DGLink Hets.emptyCASLGMorphism defaultDGLinkType defaultDGOrigin

headorempty::[[a]]->[a]
headorempty [] = []
headorempty x = head x

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
		if (length swords == 0) then [] -- error "Cannot determine DGLinkLab from empty string!"
		else
			if linktypel == [] then [] else
			[DGLink Hets.emptyCASLGMorphism (head linktypel) (stringToOrigin lorigin)]

-- | stringToLEdge returns a list with at most one LEdge
-- empty on error, error on unknown link origins (nodes)
stringToLEdge::(Map.Map String Graph.Node)->Graph.Node->String->[(Graph.LEdge DGLinkLab)]
stringToLEdge nameNodeMap targetnode linkstring =
	let
		swords = separateFromColonsNoCmt $ wordsWithQuotes linkstring 
		lfrom = case getFollows (=="From:") swords of 
			Nothing -> "" -- leads to error below 
			(Just name' ) -> unquote name'
		linklabl = stringToLink linkstring	
		sourcenode = Map.findWithDefault (error ("Unknown Node : \"" ++ lfrom ++ "\"")) lfrom nameNodeMap
	in
		if linklabl == [] then [] else
		[(sourcenode, targetnode, head linklabl)]
		
inDGToXml::DGraph->Graph.Node->(Map.Map Graph.Node String)->HXT.XmlFilter
inDGToXml dg n nodenames =
	let
		inLinks = map (\ (from,_,a) -> (from, a) ) $ Graph.inn dg n
		named = map ( \ (from, a) -> (Map.findWithDefault "unknownNode" from nodenames, a)) inLinks  
	in
	if length inLinks == 0 then HXT.txt "" else
	(HXT.etag "private" += (HXT.sattr "for" (Map.findWithDefault "unknownNode" n nodenames)))
	+= ((HXT.etag "data" += (HXT.sattr "format" "Hets-Imports" +++ HXT.sattr "pto" "Hets"))
		+= HXT.cdata (
		foldl (\ins (from, dgl) ->
			ins ++ ("From:\""++ from ++ "\" " ++ (linkToString dgl) ++ "\n")
			) "\n" named)
		)
		
inDGToXmlXN::DGraph->Graph.Node->TheoryXNSet->HXT.XmlFilter
inDGToXmlXN dg n theoryset =
	let
		inLinks = map (\ (from,_,a) -> (from,a) )  $ Graph.inn dg n
		named = map (\ (from, a) -> 
			let
				xname = case getTheoryXmlName theoryset from of
					Nothing -> "unknownNode"
					(Just xname' ) -> xname'
			in
				(xname, a) ) inLinks
		xnodename = case getTheoryXmlName theoryset n of
			Nothing -> error "Origin unknown!"
			(Just xnodename' ) -> xnodename'
	in
	if length inLinks == 0 then HXT.txt "" else
	(HXT.etag "private" += (HXT.sattr "for" xnodename))
	+= ((HXT.etag "data" += (HXT.sattr "format" "Hets-Imports" +++ HXT.sattr "pto" "Hets"))
		+= HXT.cdata (
		foldl (\ins (from, dgl) ->
			ins ++ ("From:\""++ from ++ "\" " ++ (linkToString dgl) ++ "\n")
			) "\n" named)
		)
		
inDGToXmlForPrivate::DGraph->Graph.Node->(Map.Map Graph.Node String)->HXT.XmlFilter
inDGToXmlForPrivate dg n nodenames =
	let
		inLinks = map (\ (from,_,a) -> (from, a) ) $ Graph.inn dg n
		named = map ( \ (from, a) -> (Map.findWithDefault "unknownNode" from nodenames, a)) inLinks  
	in
	if length inLinks == 0 then HXT.txt "" else
	((HXT.etag "data" += (HXT.sattr "format" "Hets-Imports" +++ HXT.sattr "pto" "Hets"))
		+= HXT.cdata (
		foldl (\ins (from, dgl) ->
			ins ++ ("From:\""++ from ++ "\" " ++ (linkToString dgl) ++ "\n")
			) "\n" named)
		)
		
-- | separates strings following colons if the string is not quoted
separateFromColonsNoCmt::[String]->[String]
separateFromColonsNoCmt strings =
	separateFromColonsC strings (\s -> (head s) == '"')

-- | separates strings following colons
separateFromColons::[String]->[String]
separateFromColons strings =
	separateFromColonsC strings (\_ -> False)

-- | separates strings following colons except on strings s where cond s is True 	
separateFromColonsC::[String]->(String->Bool)->[String]
separateFromColonsC strings cond =
	foldl (\r s ->
		let 
			parts = explode ":" s
		in
			if cond s then r ++ [s] else
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
		quote w' = ("\""++(takeWhile (/='"') w' )++"\""):(wordsWithQuotes (drop 1 (dropWhile (/='"') w' )))
wordsWithQuotes w =
	let
		word = takeWhile (\c -> (not $ Char.isSpace c) && (c /= '\"')) (dropWhile Char.isSpace w)
		rest = dropWhile Char.isSpace (dropWhile (\c -> (not $ Char.isSpace c) && (c /= '\"')) (dropWhile Char.isSpace w))
	in
		word:(wordsWithQuotes rest)
		

-- | retrieves a qualified value (prefix:localpart) from xml
-- but tries also without prefix, if no such value can be found...
getQualValue::String->String->XmlFilter
getQualValue "" localpart = getValue localpart
getQualValue prefix localpart =
	(\t -> if hasAttr (prefix ++ ":" ++ localpart) t /= []
		then
			getValue (prefix ++ ":" ++ localpart) t
		else
			getValue localpart t
	)
	

	
theoryNameFilter::HXT.XmlFilter
theoryNameFilter = (getQualValue theoryNameXMLNS theoryNameXMLAttr)

-- this is just a fragment of xpath-expressions from HXT
-- maybe(!) this can be used more effective that current methods...
nodeNamesFromXmlXP::HXT.XmlTrees->(Set.Set String)
nodeNamesFromXmlXP t = Set.fromList $
	map (\n -> xshow [n]) $
	applyXmlFilter
		(XPath.getXPath ("@"
			++theoryNameXMLNS
			++":"
			++theoryNameXMLAttr
			++" | @"
			++theoryNameXMLAttr
			++"") .> getChildren) t
			
-- remove keys from a map (will result in removing double entries when merging sets)
mapSetToSet::(Ord b)=>Map.Map a (Set.Set b)->Set.Set b
mapSetToSet mapping =
	foldl (\set (_, s) ->
		Set.union set s
		) Set.empty (Map.toList mapping)

data AnnotatedXML a = AXML { axAnn::a, axXml::HXT.XmlTrees }
	deriving Show

type AnnXMLN = AnnotatedXML Graph.Node

instance (Eq a)=>Eq (AnnotatedXML a) where
	ax1 == ax2 = (axAnn ax1) == (axAnn ax2)
	
instance (Ord a)=>Ord (AnnotatedXML a) where
	compare ax1 ax2 = compare (axAnn ax1) (axAnn ax2)
	
nodeNamesFromXml::HXT.XmlTrees->(Set.Set String)
nodeNamesFromXml t = 
	Set.fromList $ map (\n -> xshow [n]) $ applyXmlFilter ( isTag "theory" .> theoryNameFilter ) t
	
buildAXTheorySet::HXT.XmlTrees->Set.Set AnnXMLN
buildAXTheorySet t =
	let
		theories = applyXmlFilter (getChildren .> isTag "theory") t
	in
		Set.fromList $ zipWith
			(\n t' -> AXML n [t' ])
			[1..]
			theories
	
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
				theohetsnodename = idToNodeName $ read theohetsnodenames
			in
				txnl ++ [XmlNamed ((axAnn axml), theohetsnodename) theoid]
		)
		[]
		axmlset
	
sortsFromXmlTheory::HXT.XmlTrees->(Set.Set SORT)
sortsFromXmlTheory t =
	Set.fromList $ map Hets.stringToId $ map (\n -> xshow [n]) $
		applyXmlFilter (
			getChildren .> isTag "symbol" .>
			withQualSValue symbolTypeXMLNS symbolTypeXMLAttr "sort" .> getQualValue sortNameXMLNS sortNameXMLAttr) t
			
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
		
	
sortsFromXml::HXT.XmlTrees->Hets.SortsMap
sortsFromXml t =
	foldl (\map' theory ->
		let	name' = xshow $ applyXmlFilter theoryNameFilter [theory]
			sorts' = sortsFromXmlTheory [theory]
		in
			Map.insert name' sorts' map'
		) Map.empty $ applyXmlFilter (isTag "theory") t
		
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
	
findByNameWith::(Container b a)=>(a->XmlNamed c)->String->b->Maybe a
findByNameWith trans iname icon =
	find (\i -> (xnName $ trans i) == iname) (getItems icon)
	
findByNameWithAnd::(Container b a)=>(a->d)->(a->XmlNamed c)->String->b->Maybe d
findByNameWithAnd proc trans iname icon =
	case findByNameWith trans iname icon of
		Nothing -> Nothing
		(Just i) -> Just (proc i)
	
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

relsFromXmlTheory::HXT.XmlTrees->(Rel.Rel SORT)
relsFromXmlTheory t =
	let	adts = applyXmlFilter (getChildren .> isTag "adt") t
		relations = concat $ map relsFromXmlADT adts
	in
		Rel.fromList relations
	where
	relsFromXmlADT::HXT.XmlTree->[(SORT, SORT)]
	relsFromXmlADT t' =
		let	sort = Hets.stringToId $ xshow $ applyXmlFilter (getChildren .> isTag "sortdef" .> withSValue "type" "free" .> getValue "name") [t' ]
			insorts = map (\n -> Hets.stringToId $ drop 1 $ xshow [n]) $ applyXmlFilter (getChildren .> isTag "sortdef" .> getChildren .> isTag "insort" .> getValue "for") [t' ]
			-- note that we restore 'CASL-Order' here
		in	map (\n -> (n, sort)) insorts
		
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
				Nothing -> error "Relation with unknown sort!"
				(Just xs' ) -> xs'
				) xninsortss
			-- note that we restore 'CASL-Order' here
		in	map (\n -> (n, xnsort)) xninsorts
	
		
relsFromXml::HXT.XmlTrees->Hets.RelsMap
relsFromXml t =
	foldl (\map' theory ->
		let	name' = xshow $ applyXmlFilter theoryNameFilter [theory]
			rels' = relsFromXmlTheory [theory]
		in
			Map.insert name' rels' map'
		) Map.empty $ applyXmlFilter (isTag "theory") t
		
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
	
		
predsFromXmlTheory::HXT.XmlTrees->(Map.Map Id.Id (Set.Set PredType))
predsFromXmlTheory t =
	let	objsymbols = applyXmlFilter (getChildren .> isTag "symbol" .> withQualSValue symbolTypeXMLNS symbolTypeXMLAttr "object") t
		predsymbols = filter (\n -> applyXmlFilter (
				getChildren .> isTag "type" .>
				getChildren .> isTag "OMOBJ" .>
				getChildren .> isTag "OMA" .>
				getChildren .> isTag "OMS" .>
				withSValue "cd" "casl" .>
				withSValue "name" "predication") [n] /= []) objsymbols
	in
		foldl (\map' (p, pt) ->
			Map.insert p (Set.insert pt $ Map.findWithDefault Set.empty p map' ) map'
			) Map.empty $ map predFromXmlSymbol predsymbols
	where
		predFromXmlSymbol::HXT.XmlTree->(Id.Id, PredType)
		predFromXmlSymbol t' =
			let	pId = Hets.stringToId $ xshow $ applyXmlFilter (getQualValue predNameXMLNS predNameXMLAttr) [t' ]
				args = applyXmlFilter (
					getChildren .> isTag "type" .> withSValue "system" "casl" .>
					getChildren .> isTag "OMOBJ" .>
					getChildren .> isTag "OMA" .>
					getChildren .> isTag "OMS" .>
					withValue "name" (/="predication") .>
					getValue "name" ) [t' ]
			in	(pId, PredType $ map (\n -> Hets.stringToId $ xshow [n]) args)
			
type XmlNamedWONId = XmlNamedWON Id.Id

getPresentationString::String->HXT.XmlTrees->String
getPresentationString for t =
	xshow $ applyXmlFilter (getChildren .> isTag "presentation" .> withSValue "for" for .>
		getChildren .> isTag "use" .> withSValue "format" "Hets" .> 
		getChildren) t
	

predsXNWONFromXmlTheory::TheoryXNSet->Set.Set XmlNamedWONSORT->AnnXMLN->[(XmlNamedWONId, PredTypeXNWON)]
predsXNWONFromXmlTheory xntheoryset xnsortset anxml =
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
				pidxname = xshow $ applyXmlFilter (getQualValue predNameXMLNS predNameXMLAttr) (axXml panxml)
				pids = getPresentationString pidxname (axXml anxml) -- yes, reference to 'outer' xml
				pid = case pids of
					[] -> Debug.Trace.trace ("Note: No Hets-Presentation found for Predicate with Xml-ID : \"" ++ pidxname ++ "\"") $ Hets.stringToId pidxname
					_ -> read pids
				argtags = applyXmlFilter (getChildren .> isTag "type" .> withSValue "system" "casl" .>
					getChildren .> isTag "OMOBJ" .> getChildren .> isTag "OMA" .>
					getChildren .> isTag "OMS" .> withValue "name" (/="predication") ) (axXml panxml)
				argswithcds = map (\n ->
					(
						xshow $ applyXmlFilter (getValue "name") [n],
						xshow $ applyXmlFilter (getValue "cd") [n]
					)
					) argtags
				xnargs = map
					(\(axname, acd) ->
						let
							theonode = case getNodeForTheoryName xntheoryset acd of
								Nothing -> error "Unknown Theory for Argument!"
								(Just n) -> n
						in
							case findByNameAndOrigin axname theonode xnsortset of
								Nothing -> error "Unknown type of argument!"
								(Just xnarg) ->
									if (xnWOaToO xnarg) /= theonode
										then
											error "Found Argument but in wrong Theory!"
										else
											xnarg
					)
					argswithcds
			in	(XmlNamed (Hets.mkWON pid (axAnn anxml)) pidxname, PredTypeXNWON xnargs)
	
			
		
predsFromXml::HXT.XmlTrees->Hets.PredsMap
predsFromXml t =
	foldl (\map' theory ->
		let	name' = xshow $ applyXmlFilter theoryNameFilter [theory]
			preds' = predsFromXmlTheory [theory]
		in
			Map.insert name' preds' map'
		) Map.empty $ applyXmlFilter (isTag "theory") t
		
predsXNWONFromXml::TheoryXNSet->Set.Set XmlNamedWONSORT->Set.Set AnnXMLN->Map.Map XmlName [(XmlNamedWONId, PredTypeXNWON)]
predsXNWONFromXml xntheoryset xnsortset anxmlset =
	Set.fold
		(\anxml mapping ->
			let
				theopreds = predsXNWONFromXmlTheory xntheoryset xnsortset anxml
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
		
opsFromXmlTheory::HXT.XmlTrees->(Map.Map Id.Id (Set.Set OpType))
opsFromXmlTheory t =
	let	objsymbols = applyXmlFilter (getChildren .> isTag "symbol" .> withQualSValue symbolTypeXMLNS symbolTypeXMLAttr "object") t
		opsymbols = filter (\n -> applyXmlFilter (
				getChildren .> isTag "type" .>
				getChildren .> isTag "OMOBJ" .>
				getChildren .> isTag "OMA" .>
				getChildren .> isTag "OMS" .>
				withSValue "cd" "casl" .>
				withValue "name" (\n' -> n' == "function" || n' == "partial-function") ) [n] /= []) objsymbols
	in
		foldl (\map' (p, pt) ->
			Map.insert p (Set.insert pt $ Map.findWithDefault Set.empty p map' ) map'
			) Map.empty $ map opFromXmlSymbol opsymbols 
	where
		opFromXmlSymbol::HXT.XmlTree->(Id.Id, OpType)
		opFromXmlSymbol t' =
			let	oId = Hets.stringToId $ xshow $ applyXmlFilter (getQualValue opNameXMLNS opNameXMLAttr) [t' ]
				isTotal = applyXmlFilter (
					getChildren .> isTag "type" .> withSValue "system" "casl" .>
					getChildren .> isTag "OMOBJ" .>
					getChildren .> isTag "OMA" .>
					getChildren .> isTag "OMS" .>
					withSValue "name" "function") [t' ] /= []
				argsall = applyXmlFilter (
					getChildren .> isTag "type" .> withSValue "system" "casl" .>
					getChildren .> isTag "OMOBJ" .>
					getChildren .> isTag "OMA" .>
					getChildren .> isTag "OMS" .>
					withValue "name" (\n -> n /= "function" && n /= "partial-function") .>
					getValue "name" ) [t' ]
				args = take (length(argsall)-1) argsall
				res = Hets.stringToId $ xshow $ [last (argsall)]
			in	(oId, OpType (if isTotal then Total else Partial) (map (\n -> Hets.stringToId $ xshow [n]) args) res)
			
opsXNWONFromXmlTheory::TheoryXNSet->Set.Set XmlNamedWONSORT->AnnXMLN->[(XmlNamedWONId, OpTypeXNWON)]
opsXNWONFromXmlTheory xntheoryset xnsortset anxml =
	let
		objsymbols = applyXmlFilter (getChildren .> isTag "symbol" .> withQualSValue symbolTypeXMLNS symbolTypeXMLAttr "object") (axXml anxml)
		opsymbols = filter (\n -> applyXmlFilter (
				getChildren .> isTag "type" .>
				getChildren .> isTag "OMOBJ" .>
				getChildren .> isTag "OMA" .>
				getChildren .> isTag "OMS" .>
				withSValue "cd" "casl" .>
				withValue "name" (\n' -> n' == "function" || n' == "partial-function") ) [n] /= []) objsymbols
	in
		map opFromXmlSymbol (map (\n -> AXML (axAnn anxml) [n]) opsymbols) 
	where
		opFromXmlSymbol::AnnXMLN->(XmlNamedWONId, OpTypeXNWON)
		opFromXmlSymbol oanxml =
			let
				oidxname = xshow $ applyXmlFilter (getQualValue opNameXMLNS opNameXMLAttr) (axXml oanxml)
				oids = getPresentationString oidxname (axXml anxml)
				oid = case oids of
					[] -> Debug.Trace.trace ("Note: No Hets-Presentation found for Operator with Xml-ID : \"" ++ oidxname ++ "\"") $ Hets.stringToId oidxname
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
				argsallwithcds = map (\n ->
					(
						xshow $ applyXmlFilter (getValue "name") [n],
						xshow $ applyXmlFilter (getValue "cd") [n]
					)
					) argsalltags
				xnargsall = map
					(\(axname, acd) ->
						let
							theonode = case getNodeForTheoryName xntheoryset acd of
								Nothing -> error "No Theory for Argument!"
								(Just n) -> n
						in
							case findByNameAndOrigin axname theonode xnsortset of
								Nothing -> error "Unknown type of argument!"
								(Just xnarg) -> if (xnWOaToO xnarg) /= theonode
									then
										error "Found Argument but in wrong Theory!"
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
	
			
	
opsFromXml::HXT.XmlTrees->Hets.OpsMap
opsFromXml t =
	foldl (\map' theory ->
		let	name' = xshow $ applyXmlFilter theoryNameFilter [theory]
			ops' = opsFromXmlTheory [theory]
		in
			Map.insert name' ops' map'
		) Map.empty $ applyXmlFilter (isTag "theory") t
		
opsXNWONFromXml::TheoryXNSet->Set.Set XmlNamedWONSORT->Set.Set AnnXMLN->Map.Map XmlName [(XmlNamedWONId, OpTypeXNWON)]
opsXNWONFromXml xntheoryset xnsortset anxmlset =
	Set.fold
		(\anxml mapping ->
			let
				theoops = opsXNWONFromXmlTheory xntheoryset xnsortset anxml
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
	let	privates = applyXmlFilter (isTag "private") t
		theonames = map (\n -> xshow [n]) $ applyXmlFilter (getQualValue "" "for") privates
	in
		foldl (\hints name' ->
			let	pdata = xshow $ applyXmlFilter (
					withSValue "for" name' .> getChildren .>
					isTag "data" .> withSValue "pto" "Hets" .>
					withSValue "format" "Hets-Imports" .> getChildren) privates
				ldata = lines pdata
			in
				if ldata == [] then -- empty lines create no hints...
					hints
					else
					foldl (\h l ->
						let
							lablink = stringToLink l
							fromname = case getFollows (=="From:") (separateFromColonsNoCmt $ wordsWithQuotes l) of
								Nothing -> ""
								(Just n) -> unquote n
						in
							if l == [] then h -- empty lines create no hints...
								else
								if lablink == [] then -- error processing the line -> still create structure hint...
									Map.insert
										name'
										(Set.union
											(Map.findWithDefault Set.empty name' h)
											(Set.singleton (FromStructure (fromname, defaultDGLinkLab)) )
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
							) hints ldata
				) Map.empty theonames
		
importsFromXmlTheory::HXT.XmlTrees->Hets.Imports
importsFromXmlTheory t =
	let
		imports' = applyXmlFilter (getChildren .> isTag "imports") t
	in
		foldl (\imps i ->
			let
				from = drop 1 $ xshow $ applyXmlFilter (getValue "from") [i]
				mm = foldl (\(mmsm, mmfm, mmpm, mmhs) m ->
					let
						(nmmsm, nmmfm, nmmpm, nmmhs) = xmlToMorphismMap [m]
					in
						(Map.union mmsm nmmsm, Map.union mmfm nmmfm, Map.union mmpm nmmpm, Set.union mmhs nmmhs)
					) (Map.empty, Map.empty, Map.empty, Set.empty) $ applyXmlFilter (getChildren .> isTag "morphism") [i]
			in
				Set.union imps (Set.singleton (from, (Just mm)))
		) Set.empty imports'
	
importsFromXml::HXT.XmlTrees->Hets.ImportsMap
importsFromXml t =
	foldl (\map' theory ->
		let	name' = xshow $ applyXmlFilter (getQualValue "xml" "id") [theory]
			imports' = importsFromXmlTheory [theory]
		in
			Map.insert name' imports' map'
		) Map.empty $ applyXmlFilter (isTag "theory") t
		
sensFromXmlTheory::FormulaContext->HXT.XmlTrees->(Set.Set (Ann.Named CASLFORMULA))
sensFromXmlTheory fc t = Set.fromList $ unwrapFormulas fc $ applyXmlFilter (getChildren .> isTag "axiom") t

sensFromXml::FormulaContext->HXT.XmlTrees->Hets.SensMap
sensFromXml fc t = 
	foldl (\map' theory ->
		let	name' = xshow $ applyXmlFilter theoryNameFilter [theory]
			sens = sensFromXmlTheory (fc { currentName = name' } ) [theory]
			consens = conSensFromXmlTheory [theory]
		in
			Map.insert name' (Set.union sens consens) map'
		) Map.empty $ applyXmlFilter (isTag "theory") t
		
conSensFromXmlTheory::HXT.XmlTrees->(Set.Set (Ann.Named CASLFORMULA))
conSensFromXmlTheory t =
	let
		adts = applyXmlFilter (getChildren .> isTag "adt") t
	in
		Set.fromList $ map (\n -> uncurry consToSens $ extractConsFromADT [n]) adts 
	

-- | recreate non-incremental (full) mappings from the received mappings and the imports-information
createFullMaps::Hets.SortsMap->Hets.RelsMap->Hets.PredsMap->Hets.OpsMap->Hets.SensMap->Hets.ImportsMap->String->
	(Set.Set SORT, Rel.Rel SORT, Map.Map Id.Id (Set.Set PredType), Map.Map Id.Id (Set.Set OpType), Set.Set (Ann.Named CASLFORMULA))
createFullMaps sortsmap relsmap predsmap opsmap sensmap importsmap nodename =
	let
		imports' = getImports importsmap nodename
		sorts' = foldl (\ss i -> Set.union ss (Map.findWithDefault Set.empty i sortsmap))
				(Map.findWithDefault Set.empty nodename sortsmap) $ Set.toList $ Set.map fst imports'
		rels' = foldl (\rl i -> Rel.union rl (Map.findWithDefault Rel.empty i relsmap))
				(Map.findWithDefault Rel.empty nodename relsmap) $ Set.toList $ Set.map fst imports'
		preds' = foldl (\rl i -> Map.union rl (Map.findWithDefault Map.empty i predsmap))
				(Map.findWithDefault Map.empty nodename predsmap) $ Set.toList $ Set.map fst imports'
		ops' = foldl (\rl i -> Map.union rl (Map.findWithDefault Map.empty i opsmap))
				(Map.findWithDefault Map.empty nodename opsmap) $ Set.toList $ Set.map fst imports'
		sens = foldl (\rl i -> Set.union rl (Map.findWithDefault Set.empty i sensmap))
				(Map.findWithDefault Set.empty nodename sensmap) $ Set.toList $ Set.map fst imports'
		msorts = foldl(\ms mmm ->
			case mmm of
				Nothing -> ms
				(Just mm) -> Hets.addMorphismSorts mm ms
				) sorts' $ Set.toList $ Set.map snd imports' 
		mpreds = foldl(\mp mmm ->
			case mmm of
				Nothing -> mp
				(Just mm) -> Hets.addMorphismPreds mm mp
				) preds' $ Set.toList $ Set.map snd imports'
		mops = foldl(\mo mmm ->
			case mmm of
				Nothing -> mo
				(Just mm) -> Hets.addMorphismOps mm mo
				) ops' $ Set.toList $ Set.map snd imports'
	in
		(msorts, rels' , mpreds, mops, sens)
	
mapsToG_theory::(Set.Set SORT, Rel.Rel SORT, Map.Map Id.Id (Set.Set PredType), Map.Map Id.Id (Set.Set OpType), Set.Set (Ann.Named CASLFORMULA))->G_theory
mapsToG_theory (sortset, rels' , predmap, opmap, sensmap) =
	G_theory
		CASL
		(Sign sortset rels' opmap Map.empty predmap Map.empty [] [] GA.emptyGlobalAnnos ()) 
		(Prover.toThSens $ Set.toList sensmap)
		
mapsToDGNodeLab::(Set.Set SORT, Rel.Rel SORT, Map.Map Id.Id (Set.Set PredType), Map.Map Id.Id (Set.Set OpType), Set.Set (Ann.Named CASLFORMULA))->String->DGNodeLab
mapsToDGNodeLab maps nodename =
	DGNode
		(makeName $ Hets.stringToSimpleId nodename)
		(mapsToG_theory maps)
		Nothing
		Nothing
		DGBasic
		None
		LeftOpen
		
xmlToDGNodes::HXT.XmlTrees->(ImportGraph (HXT.XmlTrees, Maybe DGraph))->[DGNodeLab]
xmlToDGNodes t _ = -- ig
	let	nodenames = nodeNamesFromXml t
		importsMap' = importsFromXml t
		sortsMap' = sortsFromXml t
		relsMap' = relsFromXml t
		predsMap' = predsFromXml t
		opsMap' = opsFromXml t
		sensMap' = sensFromXml (FC importsMap' sortsMap' relsMap' predsMap' opsMap' "") t
		--ic = ImportContext importsMap sortsMap relsMap predsMap opsMap sensMap ig
	in	map
			(\n -> mapsToDGNodeLab
				(createFullMaps sortsMap' relsMap' predsMap' opsMap' sensMap' importsMap' n)
				n
			)
			$ Set.toList nodenames
			
importGraphToDGNodes::(ImportGraph (HXT.XmlTrees, Maybe DGraph))->Graph.Node->[DGNodeLab]
importGraphToDGNodes ig n =
	let
		mnode = Graph.lab ig n
		node = case mnode of
			Nothing -> error "node error!"
			(Just n' ) -> n'
		omdoc = (\(S _ (omdoc' , _)) -> applyXmlFilter (isTag "omdoc" .> getChildren) omdoc' ) node
		nodenames = nodeNamesFromXml omdoc
		importsMap' = importsFromXml omdoc
		sortsMap' = sortsFromXml omdoc
		relsMap' = relsFromXml omdoc
		predsMap' = predsFromXml omdoc
		opsMap' = opsFromXml omdoc
		sensMap' = sensFromXml (FC importsMap' sortsMap' relsMap' predsMap' opsMap' "") omdoc
		refimports = filter ( \(_,from,_) -> from /= n) $ Graph.out ig n
		refs = map ( \(_, from, (TI (theoname, _))) ->
			let
				moriginnode = Graph.lab ig from
				(S (_, ssrc) (_,modg)) = case moriginnode of
					Nothing -> error "node error (import)!"
					(Just n' ) -> n'
					-- the DG should have been created before accessing it
				odg = case modg of
					Nothing -> error "dg error"
					(Just d) -> d
				onodenum = case filter (\(_,node' ) -> (getDGNodeName node' ) == theoname ) $ Graph.labNodes odg of
					[] -> error "no such node in origin..."
					l -> fst $ head l
			in
				DGRef
					(Hets.stringToSimpleId theoname, "", 0)
					(ASL.Lib_id (ASL.Indirect_link ssrc Id.nullRange))
					onodenum
					(G_theory CASL Hets.emptyCASLSign (Prover.toThSens []))
					Nothing
					Nothing
					) refimports
	in	
		(map
			(\n' -> mapsToDGNodeLab
				(createFullMaps sortsMap' relsMap' predsMap' opsMap' sensMap' importsMap' n' )
				n'
			)
			$ Set.toList nodenames) ++ refs
		

cleanNodeName::DGNodeLab->DGNodeLab
cleanNodeName (node@(DGNode { })) =
	if isPrefix "AnonNode" (getDGNodeName node)
		then
			node { dgn_name = emptyNodeName }
		else
			node
cleanNodeName ref = ref

xmlToDGraph::HXT.XmlTrees->(ImportGraph (HXT.XmlTrees, Maybe DGraph))->DGraph
xmlToDGraph t ig =
	let	nodes = xmlToDGNodes t ig
		lnodes = (zip [1..] nodes)::[(Graph.Node, DGNodeLab)]
		--nodegraph = (Graph.mkGraph lnodes [])::DGraph
		nameNodeMap = Map.fromList $ map ( \(n, node) -> (getDGNodeName node, n) ) $ lnodes
		imports' = importsFromXml t
		importhints = createImportHints t
		ledges = foldl (
			\le (nodename, nodeimports) ->
				let	
					nodenum = Map.findWithDefault 0 nodename nameNodeMap
				in
					foldl (\le' ni ->
						let
							importnodenum = case Map.findWithDefault 0 ni nameNodeMap of
								0 -> Debug.Trace.trace ("Cannot find node for \"" ++ ni ++ "\"!") 0
								x -> x
							filteredimporthints = Set.filter (\h -> (fromName h) == ni) $ Map.findWithDefault Set.empty nodename importhints
						in	
							le' ++
							if Set.null filteredimporthints
								then
									[(importnodenum, nodenum, defaultDGLinkLab)]
								else
									map (\ih -> (importnodenum, nodenum, getIHLink ih)) $ Set.toList filteredimporthints
						) le $ Set.toList nodeimports
				) [] $ Map.toList $ Map.map (Set.map fst) imports'
		validedges = foldl (\e newe@(n,m,_) ->
			if (n==0) || (m==0) then
				Debug.Trace.trace ("Invalid Edge found from " ++ (show n) ++ " to " ++ (show m) ++ "...") e
				else
				e++[newe]
				) [] ledges
		cleannodes = map (\(n,node) -> (n, cleanNodeName node)) lnodes  
	in
		Graph.mkGraph cleannodes validedges
		
getNodeSignature::(ImportGraph (HXT.XmlTrees, Maybe DGraph))->(Maybe DGNodeLab)->CASLSign
getNodeSignature igdg mnode =
	case mnode of
		Nothing -> Hets.emptyCASLSign
		(Just node@(DGNode {})) ->
			case Hets.getCASLSign $ dgn_sign node of
				Nothing -> Hets.emptyCASLSign
				(Just sign) -> sign
		(Just (DGRef { dgn_libname = lname, dgn_node = rnode})) ->
			let
				libnode = filter (\(_, (S (_,src) (_,_))) -> src == (show lname)) $ Graph.labNodes igdg
			in
				case libnode of
					(l:_) ->
						case l of
							(_, (S (_,_) (_,(Just ldg)))) -> getNodeSignature igdg $ Graph.lab ldg rnode 
							_ -> Hets.emptyCASLSign
					_ -> Hets.emptyCASLSign

importGraphToDGraph::(ImportGraph (HXT.XmlTrees, Maybe DGraph))->Graph.Node->DGraph
importGraphToDGraph ig n =
	let
		mnode = Graph.lab ig n
		node = case mnode of
			Nothing -> error "node error!"
			(Just n' ) -> n'
		omdoc = (\(S _ (omdoc' , _)) -> applyXmlFilter (isTag "omdoc" .> getChildren) omdoc' ) node
		nodes = importGraphToDGNodes ig n
		lnodes = (zip [1..] nodes)::[(Graph.Node, DGNodeLab)]
		--nodegraph = (Graph.mkGraph lnodes [])::DGraph
		nameNodeMap = Map.fromList $ map ( \(n' , node' ) -> (getDGNodeName node' , n' ) ) $ lnodes
		imports' = importsFromXml omdoc
		importhints = createImportHints omdoc
		ledges = foldl (
			\le (nodename, nodeimports) ->
				let	
					nodenum = Map.findWithDefault 0 nodename nameNodeMap
					tnode = case map snd $ filter (\(n' ,_) -> n' == nodenum) lnodes of
						(l:_) -> l
						_ -> error "node error!"
					targetsign = getNodeSignature ig (Just tnode)
					nodeimporthints = Map.findWithDefault Set.empty nodename importhints
					importsfrom = map (\(a,_) -> a) $ Set.toList nodeimports
					-- the omdoc-imports have limited support for the imports
					-- used in a dgraph. some import-hints have no import-tag in
					-- the omdoc
					importhintswithoutimports = Set.filter (\ih -> not $ elem (fromName ih) importsfrom) nodeimporthints 
				in
					(foldl (\le' (ni, mmm) ->
						let
							importnodenum = case Map.findWithDefault 0 ni nameNodeMap of
								0 -> Debug.Trace.trace ("Cannot find node for \"" ++ ni ++ "\"!") 0
								x -> x
							snode = case map snd $ filter (\(n' ,_) -> n' == importnodenum) lnodes of
								(l:_) -> l
								_ -> error "node error!"
							sourcesign = getNodeSignature ig (Just snode)
							filteredimporthints = Set.filter (\h -> (fromName h) == ni) nodeimporthints
							ddgl = case mmm of
								Nothing -> defaultDGLinkLab
								(Just mm) -> defaultDGLinkLab { dgl_origin = DGTranslation, dgl_morphism = (Hets.makeCASLGMorphism $ (Hets.morphismMapToMorphism mm) { mtarget=targetsign, msource = sourcesign}) }
						in	
							le' ++
							if Set.null filteredimporthints
								then
									[(importnodenum, nodenum, ddgl)]
								else
									map (\ih ->
										let
											ihlink = getIHLink ih
											link = case dgl_origin ihlink of
											-- this is rather ugly, but else morphisms would be lost for now...
												DGTranslation -> ihlink { dgl_morphism = dgl_morphism ddgl }
												_ -> ihlink
										in
											(importnodenum, nodenum, link)
										) $ Set.toList filteredimporthints
						) le $ Set.toList nodeimports)
						-- add further imports
						++
						(map (\ih ->
							let
								ni = fromName ih
								importnodenum = case Map.findWithDefault 0 ni nameNodeMap of
									0 -> Debug.Trace.trace ("Cannot find node for \"" ++ ni ++ "\"!") 0
									x -> x
							in
								(importnodenum, nodenum, getIHLink ih)
								) $ Set.toList importhintswithoutimports)
				) [] $ Map.toList imports'
		validedges = foldl (\e newe@(n' ,m,_) ->
			if (n' ==0) || (m==0) then
				Debug.Trace.trace ("Invalid Edge found from " ++ (show n' ) ++ " to " ++ (show m) ++ "...") e
				else
				e++[newe]
				) [] ledges
		cleannodes = map (\(n' , node' ) -> (n' , cleanNodeName node' )) lnodes  
	in
		Graph.mkGraph cleannodes validedges
		
getOmdocID::HXT.XmlTrees->String
getOmdocID = xshow . applyXmlFilter (isTag "omdoc" .> getQualValue "xml" "id")
		
omdocToDevGraph::HXT.XmlTrees->(DGraph, String)
omdocToDevGraph t = (xmlToDGraph (applyXmlFilter (isTag "omdoc" .> getChildren) t) (Graph.mkGraph [] []), getOmdocID t) 
	
dgNameToLnDGLe::(DGraph, String)->(ASL.LIB_NAME,DGraph,LibEnv)
dgNameToLnDGLe (dg, name' ) =
	let
		libname = (ASL.Lib_id (ASL.Indirect_link name' Id.nullRange))
		--lenv = Map.fromList $ [ (libname, (GA.emptyGlobalAnnos, Map.empty, dg))  ]
		lenv = Map.fromList $ [ (libname, emptyGlobalContext { devGraph = dg } )  ]
	in
		(libname, dg, lenv)
		
showDGAndName::(DGraph, String)->(IO ())
showDGAndName (dg,name' ) =
	Hets.showGraph name' DOptions.defaultHetcatsOpts $
		(\a -> (Just a) ) $
		(\(a,_,c) -> (a, c)) $
		dgNameToLnDGLe (dg, name' )
		
getCatalogueInformation::HXT.XmlTrees->(Map.Map String String)
getCatalogueInformation t =
	let
		catalogue = applyXmlFilter (getChildren .> isTag "catalogue") t
		locs = applyXmlFilter (getChildren .> isTag "loc") catalogue
		list = foldl (\l loc ->
			l ++ [ (xshow $ applyXmlFilter (getValue "theory") [loc], xshow $ applyXmlFilter (getValue "omdoc") [loc]) ]
			) [] locs
	in
		Map.fromList list
		
-- | theory name, theory source (local)
data TheoryImport = TI (String, String)

instance Show TheoryImport where
	show (TI (tn, ts)) = ("Import of \"" ++ tn ++ "\" from \"" ++ ts ++ "\".")

-- | source name, source (absolute)
data Source a = S (String, String) a 

instance Show (Source a) where
	show (S (sn, sf) _) = ("Source \"" ++ sn ++ "\" File : \"" ++ sf ++ "\".");

type ImportGraph a = Tree.Gr (Source a) TheoryImport 

getImportMapFG::String->(IO ((String,HXT.XmlTrees,String), (Map.Map String String)))
getImportMapFG filename =
	do
		curdir <- System.Directory.getCurrentDirectory
		cfn <- System.IO.Error.catch
			(System.Directory.canonicalizePath filename)
			(\_ -> putStrLn ("Error canonicalizing...") >> return filename)
		-- putStrLn ("Processing : " ++ filename ++ " (" ++ cfn ++ ")")
		cfp <- return
			( reverse $
				dropWhile (\c -> not $ elem c [ '/','\\' ]) $ reverse cfn)
		omdoc <- Control.Exception.catch
			(loadOmdoc cfn -- >>= \od ->
			--	(putStrLn $! (getOmdocID od)) >> return od
			)
			(\_ ->
				putStrLn ("Error loading \"" ++ cfn ++ "\"...") >>
				return (HXT.txt "" emptyRoot)
			)
		omdocid <- return (getOmdocID omdoc)
		catmap <- return (getCatalogueInformation omdoc)
		if not $ null cfp 
			then
				do
					-- putStrLn ("Changing Path to : \"" ++ cfp ++ "\"")
					System.IO.Error.catch
						(System.Directory.setCurrentDirectory cfp)
						(\_ -> putStrLn
							("Could not change path to \"" ++ cfp ++  "\"")
						)
			else
				return ()
		System.Directory.setCurrentDirectory curdir
		return ((omdocid, omdoc, cfn), catmap)
		
first::(a->Bool)->[a]->(Maybe a)
first _ [] = Nothing
first f (l:r) =
	if f l
		then
			(Just l)
		else
			first f r
			
firstM::(Monad m)=>(a->Bool)->[m a]->(m (Maybe a))
firstM _ [] = return Nothing
firstM test (l:r) =
	do
		v <- l
		if test v
			then
				return (Just v)
				else
				firstM test r

-- | tries to find a file by first searching for it in the current
-- directory and then in a list of given directories (in the order given)
-- the directory will be taken as they are. If they are relative, they will be
-- searched relative to the current directory
findFile::FilePath->[FilePath]->(IO (Maybe FilePath))
findFile file include =
	let
		isRelative = (head file) /= '/'
	in	
		if not isRelative
			then
				do
				System.Directory.doesFileExist file >>= \r ->
					if r 
						then
							return (Just file)
						else
							return Nothing
			else
				(firstM snd $
					map 
						(\f -> System.Directory.doesFileExist f >>=
							\r -> return (f,r))
							(file:(map (++"/"++file) include)))
				>>= \mfp -> case mfp of
					Nothing -> return Nothing
					(Just (f,_)) -> return (Just f)

-- | creates an import graph for an omdoc-file.
-- you can specify a list of directories to look for files in
-- the current directory will automatically be added to this list (and passed
-- to all subsequent file-searches).
makeImportGraph::String->[String]->(IO (ImportGraph HXT.XmlTrees))
makeImportGraph filename includes =
	do
	fn <- findFile filename includes >>= \mfp -> case mfp of
		Nothing -> return (error "Cannot find this file : \"" ++ filename ++ "\"")
		(Just f) -> return f
	curdir <- System.Directory.getCurrentDirectory
	((omdocid, omdoc, cfn), imap) <- getImportMapFG fn
	nodeone <- return (1, S (omdocid, cfn) omdoc)
	foldl (\gio imp ->
		do
			gio >>= \g ->
				extendImportGraph g 1 (TI imp) (includes++[curdir])
			) (return (Graph.mkGraph [nodeone] [])) $ Map.toList imap
		
	
extendImportGraph::(ImportGraph HXT.XmlTrees)->Graph.Node->TheoryImport->[String]->(IO (ImportGraph HXT.XmlTrees))
extendImportGraph ig n (TI (thn, src)) includes =
	do
		curdir <- System.Directory.getCurrentDirectory 
		(S (_ , source) _) <- return ((\(Just a) -> a) $ Graph.lab ig n)
		sourcepath <- return (reverse $ dropWhile (\c -> not $ elem c ['\\','/']) $ reverse source)
		if null sourcepath
			then
				return ()
			else
				System.IO.Error.catch
					(System.Directory.setCurrentDirectory sourcepath)
						(\_ -> putStrLn ("Could not change path to \"" ++ sourcepath ++  "\""))
		srcfp <- findFile src includes >>= \mfp -> case mfp of
			Nothing -> putStrLn ("Cannot find this file : \"" ++ src ++ "\"") >> return src
			(Just f) -> return f
		nodenum <- return (length $ Graph.nodes ig)
		((omdocid, omdoc, cfn), imap) <- getImportMapFG srcfp
		matchingNodes <- return (filter (\(_, (S (iname, isrc) _)) -> iname == omdocid && isrc == cfn ) $ Graph.labNodes ig)
		newnode <- return
			(if null matchingNodes
				then
					Debug.Trace.trace ("Creating new node for \"" ++ omdocid ++ "\"") (nodenum+1, S (omdocid, cfn) omdoc)
				else
					Debug.Trace.trace ("Using existing node for \"" ++ omdocid ++ "\"") $ head matchingNodes
			)
		newnodenum <- return ( (\(nn, _) -> nn) newnode )
		newedge <- return (n, newnodenum, TI (thn, src))
		newgraph <- return (Graph.insEdge newedge $ if null matchingNodes then Graph.insNode newnode ig else ig)
		newig <- (foldl (\nigio (thname, thsrc) ->
			do
				nigio >>= \nig ->
					extendImportGraph nig newnodenum (TI (thname, thsrc)) includes
				) (return newgraph) $ Map.toList imap)
		System.Directory.setCurrentDirectory curdir
		return newig

		
-- if there is a cycle in the imports this will fail because the algorithm
-- processes only omdoc's that do import from already processed omdoc's or do
-- not import at all.
processImportGraph::(ImportGraph HXT.XmlTrees)->(ImportGraph (HXT.XmlTrees, Maybe DGraph))
processImportGraph ig =
	let
		-- create hybrid graph containing already processed DGs (none at first)
		hybrid = Graph.mkGraph
			(map (\(n, S a b) -> (n, S a (b, Nothing))) $ Graph.labNodes ig)
			(Graph.labEdges ig) :: (ImportGraph (HXT.XmlTrees, (Maybe DGraph)))
		-- create all DG's
		processed = process hybrid
	in
		processed
	where
		-- transform one node's omdoc-content to a DGraph and proceed until
		-- no more transformations are possible
		process ::
			(ImportGraph (HXT.XmlTrees, (Maybe DGraph))) ->
			(ImportGraph (HXT.XmlTrees, (Maybe DGraph)))
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
							--	(\(_, S _ (omdoc, _)) -> omdoc) changednode
							changednodenum =
								(\(nodenum, _) -> nodenum) changednode
							dg = importGraphToDGraph igxmd changednodenum
							-- name = (\(_, (S (nname,_) _)) -> nname) changednode
							-- create the altered node
							newnode = (\(nodenum, S a (omdoc,_)) ->
								(nodenum, S a (omdoc, Just dg))) changednode
							-- fetch all other nodes
							othernodes = filter
								(\(n,_) -> n /= changednodenum) $
									Graph.labNodes igxmd
						in
							-- start the next round with the new graph
							process $ Graph.mkGraph
								(newnode:othernodes)
								(Graph.labEdges igxmd)
								
hybridGToDGraphG::(ImportGraph (HXT.XmlTrees, Maybe DGraph))->(ImportGraph DGraph)
hybridGToDGraphG ig =
	Graph.mkGraph
		( map (\(n, (S a (_,mdg))) ->
			let
				dg = case mdg of
					Nothing -> error "Cannot convert hybrid with unresolved DGraphs..."
					(Just dg' ) -> dg'
			in
				(n, (S a dg))
				) $ Graph.labNodes ig)
		(Graph.labEdges ig)
		
dGraphGToLibEnv::(ImportGraph DGraph)->(ASL.LIB_NAME, DGraph, LibEnv)
dGraphGToLibEnv ig =
	let
		nodes = map (\(_,n) -> n) $ Graph.labNodes ig
		firstnode = case nodes of
			[] -> error "empty graph..."
			l -> head l
		firstsrc = (\(S (_,src) _) -> src) firstnode
		firstdg = (\(S _ dg) -> dg) firstnode
		lenv = Map.fromList $ map ( \(S (_, src) dg) ->
					(
						(ASL.Lib_id (ASL.Indirect_link src Id.nullRange)),
						--(GA.emptyGlobalAnnos, Map.empty, dg)
						emptyGlobalContext { devGraph = dg }
					)
					) nodes
	in
		(ASL.Lib_id (ASL.Indirect_link firstsrc Id.nullRange), firstdg, lenv)
		
unwrapLinkSource::ASL.LIB_NAME->String
unwrapLinkSource
	(ASL.Lib_id (ASL.Indirect_link src _)) = src
unwrapLinkSource _ = error "Wrong application of unwrapLinkSource!"
		
libEnvToDGraphG::(ASL.LIB_NAME, DGraph, LibEnv)->(ImportGraph DGraph)
libEnvToDGraphG (ln,dg,lenv) =
	let
		input = (:) (ln,dg) $ map (\(ln' , gc) -> (ln', (devGraph gc) )) .
				filter (\(ln' ,_) -> ln' /= ln) $
				Map.toList lenv
	in
		makeIG input
	where
		makeIG::[(ASL.LIB_NAME, DGraph)]->(ImportGraph DGraph)
		makeIG input =
			let
				(lnodes, edges) = foldl (\(lnodes' , edges' ) (libname, dg' ) ->
					let
						nodenum = (+) 1 $ length lnodes'
						node = (nodenum, S (splitFile . fst . splitPath $ unwrapLinkSource libname, unwrapLinkSource libname) dg' )
						refs = filter isDGRef . map snd $ Graph.labNodes dg'
						imports' = map (\n -> (nodenum, (getDGNodeName n, unwrapLinkSource $ dgn_libname n))) refs
					in
						(lnodes' ++ [node], edges' ++ imports' )
						) ([],[]) input
				ledges = foldl (\ledges' (target, (thname, libname)) ->
					let
						source = case filter (\(_, S (_,ssrc) _) -> ssrc == libname) lnodes of
							[] -> Debug.Trace.trace ("No source found for " ++ libname ++ " in " ++ (show $ map (\(S (_,src) _) -> src) $ map snd lnodes)) 0
							sourcelist -> fst $ head sourcelist
					in
						(source, target, TI (thname, libname)):ledges'
						) [] edges
			in
				Graph.mkGraph lnodes ledges
				
-- | separates the path and filename part from a filename, first element is the
-- name, second the path (without last delimiter)
splitPath::String->(String, String)
splitPath f = case explode "/" f of
	[x] -> (x,"")
	l -> (last l, joinWith '/' $ init l)

-- | returns the name of a file without extension
splitFile::String->String
splitFile file =
	let
		filenameparts = explode "." file
	in
		case (length filenameparts) of
			1 -> file
			2 -> case head filenameparts of
					"" -> "."++(last filenameparts)
					fn -> fn
			_ -> joinWith '.' $ init filenameparts 
	
-- | returns an 'omdoc-version' of a filename (e.g. test.env -> test.omdoc)
asOmdocFile::String->String
asOmdocFile file =
	let
		parts = splitFile' file
		fullfilename = last parts
		filenameparts = explode "." fullfilename
		(filename, mfileext) =
			case (length filenameparts) of
				0 -> ("", Nothing)
				1 -> (head filenameparts, Nothing)
				2 -> case head filenameparts of
						"" -> ("."++(last filenameparts), Nothing)
						fn -> (fn, Just (last filenameparts))
				_ -> ( joinWith '.' $ init filenameparts, Just (last filenameparts)) 
	in
		case mfileext of
			Nothing -> joinFile $ (init parts) ++ [filename ++ ".omdoc"]
			(Just fileext) ->
				case map toLower fileext of
					"omdoc" -> file
					_ -> joinFile $ (init parts) ++ [filename ++ ".omdoc"]
	where
	splitFile' ::String->[String]
	splitFile' = explode "/"
	joinFile::[String]->String
	joinFile = implode "/"
		
-- | converts all DGraph-Nodes to XmlTrees-Nodes using 'devGraphToOmdoc' and
-- the name extracted from the libname
dGraphGToXmlG::(ImportGraph DGraph)->(ImportGraph (HXT.XmlTrees))
dGraphGToXmlG ig =
	let
		nodes = map (\(n, (S i@(name' ,_) dg)) ->
			(n, S i (devGraphToOmdoc dg name' ) ) ) $ Graph.labNodes ig
	in
		Graph.mkGraph nodes $ Graph.labEdges ig
		
fileSandbox::String->String->String
fileSandbox [] file = file
fileSandbox sb file =
	sb ++ "/" ++ case head file of
		'/' -> tail file
		_ -> file

-- | writes an XmlTrees-Graph to disk relative to a given directory
-- will create directory-structures from libnames
writeXmlG::String->(ImportGraph (HXT.XmlTrees))->String->IO ()
writeXmlG dtduri ig sandbox =
	let
		nodes = map snd $ Graph.labNodes ig
	in
		(mapM (\(S (name' ,file) x) ->
			let
				omfile = fileSandbox sandbox $ asOmdocFile file
			in
				putStrLn ("Writing \"" ++ name' ++ "\" to \"" ++ omfile ++ "\"") >>
				System.Directory.createDirectoryIfMissing True (snd $ splitPath omfile) >>
				writeOmdocDTD dtduri x omfile
			) nodes) >> return ()
		
			
-- | shows a developement-graph and it's environment using the
-- uniform-workbench			
showdg::(ASL.LIB_NAME, LibEnv)->IO ()
showdg (ln,lenv) =
	-- dho is 'defaultHetcatsOpts' (not visible here)...
	Hets.showGraph "" Hets.dho (Just (ln, lenv))
	 
showLink::DGraph->Graph.Node->Graph.Node->String
showLink dg n1 n2 =
	(getDGNodeName $ (\(Just a) -> a) $ Graph.lab dg n1)
	++ " -> " ++
	(getDGNodeName $ (\(Just a) -> a) $ Graph.lab dg n2)
	
showLinkType::DGLinkType->String
showLinkType lt' = case lt' of 
        LocalDef -> "LocalDef"
        GlobalDef -> "GlobalDef"
        HidingDef -> "HidingDef"
        FreeDef _ -> "FreeDef"
        CofreeDef _ -> "CofreeDef"
	LocalThm _ _ _ -> "LocalThm"
	GlobalThm _ _ _ -> "GlobalThm"
	HidingThm _ _ -> "HidingThm"
        FreeThm _ _ -> "FreeThm"
	
showEdge::DGLinkLab->String
showEdge ll = showLinkType (dgl_type ll)
	
showLinks::DGraph->[String]
showLinks dg =
	map (\(a,b,edge) -> (showLink dg a b) ++ " (" ++ (showEdge edge) ++ ")") $ Graph.labEdges dg
	

-- | get all imports for a node (recursive)
-- note : this is used for acyclic imports only
getImports::Hets.ImportsMap->String->Hets.Imports
getImports importsmap nodename =
	let currentimports = Map.findWithDefault Set.empty nodename importsmap
	in
		foldl (\is (i,_) ->
			Set.union is (getImports importsmap i)
			) currentimports $ Set.toList currentimports


-- | this function just searches for an edge in the DGraph that matches a certain
-- edge and then returns it with the connecting node numbers...
getFullEdge::Static.DevGraph.DGraph->Static.DevGraph.DGLinkLab->(Maybe (Graph.Node, Graph.Node, Static.DevGraph.DGLinkLab))
getFullEdge dg ll = let edges = Graph.labEdges dg
		    in
		    findEdge edges ll where
		    findEdge::[(Graph.Node, Graph.Node, Static.DevGraph.DGLinkLab)]->Static.DevGraph.DGLinkLab->(Maybe (Graph.Node, Graph.Node, Static.DevGraph.DGLinkLab))
		    findEdge [] _ = Nothing
		    findEdge ((labedge@(_, _, ll' )):rest) ll'' = if ll' == ll'' then (Just labedge) else findEdge rest ll''
		    
-- | this is a more practical than mathmatical approach...
-- You cannot deny, it is readable...
processConservativity::Static.DevGraph.Conservativity->(HXT.XmlTree->HXT.XmlTrees)
processConservativity None = (HXT.etag "OMSTR" += HXT.txt "Conservativity: None") +++ xmlNL 
processConservativity Cons = (HXT.etag "OMSTR" += HXT.txt "Conservativity: Cons") +++ xmlNL
processConservativity Mono = (HXT.etag "OMSTR" += HXT.txt "Conservativity: Mono") +++ xmlNL
processConservativity Def = (HXT.etag "OMSTR" += HXT.txt "Conservativity: Def") +++ xmlNL


nodeNameForXml::String->Graph.Node->String
nodeNameForXml "" n = "anonnode:"++(show n)
nodeNameForXml s _ = s
				
libNameToXml::ASL.LIB_NAME->(HXT.XmlTree->HXT.XmlTrees)
libNameToXml (ASL.Lib_version lid lvs) = (HXT.etag "OMA" += (
					(HXT.etag "OMS" += (HXT.sattr "cd" "hets" +++ HXT.sattr "name" "lib-version"))
					+++
					(libIdToXml lid) +++ xmlNL +++ (libVsToXml lvs)
					)) +++ xmlNL
libNameToXml (ASL.Lib_id lid) = (HXT.etag "OMA" += (
					(HXT.etag "OMS" += (HXT.sattr "cd" "hets" +++ HXT.sattr "name" "lib-id"))
					+++
					libIdToXml lid)
					) +++ xmlNL

libIdToXml::ASL.LIB_ID->(HXT.XmlTree->HXT.XmlTrees)
libIdToXml (ASL.Direct_link url _) = (HXT.etag "OMA" += (
					(HXT.etag "OMS" += (HXT.sattr "cd" "hets" +++ HXT.sattr "name" "direct-link"))
					+++ (HXT.etag "OMSTR" += (HXT.txt url)))) +++ xmlNL
libIdToXml (ASL.Indirect_link path _) = (HXT.etag "OMA" += (
					(HXT.etag "OMS" += (HXT.sattr "cd" "hets" +++ HXT.sattr "name" "indirect-link"))
					+++ (HXT.etag "OMSTR" += (HXT.txt path)))) +++ xmlNL
					
libVsToXml::ASL.VERSION_NUMBER->(HXT.XmlTree->HXT.XmlTrees)
libVsToXml (ASL.Version_number sl _) = (HXT.etag "OMA" += (
					(HXT.etag "OMS" += (HXT.sattr "cd" "hets" +++ HXT.sattr "name" "version-number"))
					+++ ( foldl (\sx s -> sx +++ (HXT.etag "OMSTR" += (HXT.txt s)) +++ xmlNL) (HXT.txt "") sl )))
				+++ xmlNL
					
				
-- | this function takes care of 'rendering' the DGRef to Xml
makeRefTheory::String->Graph.Node->(HXT.XmlTree->HXT.XmlTrees)
makeRefTheory libname node =
	(HXT.etag "theory" += (
		HXT.sattr "id" "reference"
		+++ xmlNL
		+++ (HXT.etag "OMOBJ" += (
			HXT.etag "OMA" += (
				-- I defined a symbol for the fetching...
				-- maybe this should be done with metadata,
				-- as it is not at all mathmaticaly relevant...
				(HXT.etag "OMS" += (HXT.sattr "cd" "hets" +++ HXT.sattr "name" "getnode"))
				+++ (HXT.etag "OMSTR" += (HXT.txt libname))
				+++ (HXT.etag "OMI" += (HXT.txt (show node)))
				)
			))
		+++ xmlNL
			)) +++ xmlNL

-- DGNODELABTOXML END

-- We also need to build up a catalogue for all imported theories

-- BUILDCATALOGUE BEGIN
makeOmdocCatalogue::[(String, String, String)]->(HXT.XmlTree->HXT.XmlTrees)
makeOmdocCatalogue [] = HXT.txt ""
makeOmdocCatalogue t =	(HXT.etag "catalogue" += (
				foldl (\_ (t' ,o' ,c) ->
					(HXT.etag "loc" += (HXT.sattr "theory" t' +++ HXT.sattr "omdoc" o' +++ HXT.sattr "cd" c))
					+++ xmlNL) (HXT.txt "") t
				)
			) +++ xmlNL

buildCatalogue::Static.DevGraph.DGraph->[(String, String, String)]
buildCatalogue dg =	let	justlabnodes = map (\(_,a)->a) $ Graph.labNodes dg
				dgrefs = filter Static.DevGraph.isDGRef justlabnodes
			in
				foldl (\list (DGRef _ libname node _ _ _) ->
					list ++ [(show node, (getLibURI libname), caslS)])
					[] dgrefs
					
getLibURI::ASL.LIB_NAME->String
getLibURI (ASL.Lib_version libid _) = show libid
getLibURI (ASL.Lib_id libid) = show libid

-- BUILDCATALOGUE END

-- | sadly '_' is also valid in Names, so this functions tries to catch this
-- by assuming that the extension is the string after the last '_' but only
-- if there is a number at the end...
stringToNodeName ::String->Static.DevGraph.NODE_NAME
stringToNodeName s = let extNumS = reverse (takeWhile (\x -> x /= '_')  (reverse s))
		     in
		     if (length extNumS) == (length s) then (Hets.stringToSimpleId s, "", 0)
			else
			  let numS = reverse (takeWhile (\x -> elem x ['0'..'9']) (reverse extNumS))
			      realExt = take ((length extNumS)-(length numS)) extNumS
			  in
			  if (numS == "") then (Hets.stringToSimpleId s, "", 0) else
			  	(Hets.stringToSimpleId (take (((length s) - length (extNumS)) - 1) s), realExt, (read numS)::Int)
				
xmlToLibName::HXT.XmlTrees->ASL.LIB_NAME
xmlToLibName t = if applyXmlFilter (getChildren .> isTag "OMS" .> withSValue "cd" "hets" .> withSValue "name" "lib-version") t /= []
			then ASL.Lib_version (xmlToLibId [(applyXmlFilter (getChildren .> isTag "OMA") t)!!0]) (xmlToLibVs [(applyXmlFilter (getChildren .> isTag "OMA") t)!!1])
			else ASL.Lib_id (xmlToLibId $ applyXmlFilter (getChildren .> isTag "OMA") t)
			
xmlToLibId::HXT.XmlTrees->ASL.LIB_ID
xmlToLibId t = if applyXmlFilter (getChildren .> isTag "OMS" .> withSValue "cd" "hets" .> withSValue "name" "direct-link") t /= []
			then ASL.Direct_link (xshow $ applyXmlFilter (getChildren .> isTag "OMSTR" .> getChildren) t) Id.nullRange
			else ASL.Indirect_link (xshow $ applyXmlFilter (getChildren .> isTag "OMSTR" .> getChildren) t) Id.nullRange
			
xmlToLibVs::HXT.XmlTrees->ASL.VERSION_NUMBER
xmlToLibVs t = 	let	stringsx = applyXmlFilter (getChildren .> isTag "OMSTR" .> getChildren) t
		in
		   ASL.Version_number (foldl (\sl sx -> sl ++ [xshow [sx]]) [] stringsx) Id.nullRange

-- XMLTONODES END

-- | helper-function to get a node from a DGraph by Name
findNode::Static.DevGraph.DGraph->String->(Graph.LNode Static.DevGraph.DGNodeLab)
findNode dg name' = findNode' name' $ Graph.labNodes dg where
	findNode' ::String->[Graph.LNode Static.DevGraph.DGNodeLab]->(Graph.LNode Static.DevGraph.DGNodeLab)
	findNode' _ [] = error ("No such Node \"" ++ name' ++ "\"")
	findNode' name'' ((n,node):rest) = if (Static.DevGraph.getDGNodeName node) == name'' then (n, node)
					else findNode' name'' rest

-- | backparsing of origin					
xmlToOrigin::HXT.XmlTrees->Static.DevGraph.DGOrigin
xmlToOrigin t = let orig_string = xshow $ applyXmlFilter (isTag "CMP" .> getChildren .> isTag "OMOBJ" .> getChildren .> isTag "OMSTR" .> getChildren) t
		in
		stringToOrigin orig_string
		
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
	| otherwise = if isPrefix "DGSpecInst " s then
				DGSpecInst (Hets.stringToSimpleId (drop (length "DGSpecInst ") s))
		      else
		      if isPrefix "DGView " s then
				DGView (Hets.stringToSimpleId (drop (length "DGView ") s))
		      else
		      if isPrefix "DGFitView " s then
				DGFitView (Hets.stringToSimpleId (drop (length "DGFitView ") s))
		      else
		      if isPrefix "DGFitViewImp " s then
				DGFitViewImp (Hets.stringToSimpleId (drop (length "DGFitViewImp ") s))
		      else
		      if isPrefix "DGFitViewA " s then
				DGFitViewA (Hets.stringToSimpleId (drop (length "DGFitViewA ") s))
		      else
		      if isPrefix "DGFitViewAImp " s then
				DGFitViewAImp (Hets.stringToSimpleId (drop (length "DGFitViewAImp ") s))
		      --else error ("No such origin \"" ++ s ++ "\"")
		      else DGBasic
		      
buildMaps::HXT.XmlTrees->(Map.Map SORT SORT, Map.Map (Id.Id, OpType) (Id.Id, FunKind), Map.Map (Id.Id, PredType) Id.Id)
buildMaps t = foldl (\(sm,fm,pm) x ->
			let	patternoo = applyXmlFilter (getChildren .> isTag "pattern" .> getChildren .> isTag "OMOBJ") [x]
				valueoo = applyXmlFilter (getChildren .> isTag "value" .> getChildren .> isTag "OMOBJ") [x]
			in
			if applyXmlFilter (getChildren .> isTag "OMS") patternoo /= []
				then
					let 	sort1 = Hets.stringToId $ xshow $ applyXmlFilter (getChildren .> isTag "OMS" .> getValue "name") patternoo
						sort2 = Hets.stringToId $ xshow $ applyXmlFilter (getChildren .> isTag "OMS" .> getValue "name") valueoo
					in
						(Map.insert (sort1) (sort2) sm, fm, pm)
			else
			if applyXmlFilter (getChildren .> isTag "OMBIND" .> getChildren .> isTag "OMATTR" .> getChildren .> isTag "OMATP" .> getChildren .> isTag "OMS" .> withSValue "name" "predication") patternoo /= []
				then
					let	id1 = Hets.stringToId $ xshow $ applyXmlFilter (getChildren .> isTag "OMBIND" .> getChildren .> isTag "OMATTR" .> getChildren .> isTag "OMS" .> withValue "name" (/="result") .> getValue "name") patternoo
						parx = applyXmlFilter (getChildren .> isTag "OMBIND" .> getChildren .> isTag "OMBVAR" .> getChildren) patternoo
						par = foldl (\pl px ->
								pl ++ [Hets.stringToId $ xshow $ applyXmlFilter (isTag "OMATTR" .> getChildren .> isTag "OMATP" .> getChildren .> isTag "OMS" .> withValue "name" (/=typeS) .> getValue "name") [px]]
								) [] parx
						id2 = Hets.stringToId $ xshow $ applyXmlFilter (isTag "OMATTR" .> getChildren .> isTag "OMS" .> withValue "name" (/="result") .> getValue "name") valueoo
					in
						(sm, fm, Map.insert (id1, (PredType par)) (id2) pm)
			else
			if applyXmlFilter (getChildren .> isTag "OMBIND" .> getChildren .> isTag "OMATTR" .> getChildren .> isTag "OMATP" .> getChildren .> isTag "OMS" .> withValue "name" ( \s -> (s == "Total" || s == "Partial")) ) patternoo /= []
				then
					let	ft1S = xshow $ applyXmlFilter (getChildren .> isTag "OMBIND" .> getChildren .> isTag "OMATTR" .> getChildren .> isTag "OMATP" .> getChildren .> isTag "OMS" .> withValue "name" ( \s -> (s == "Total" || s == "Partial") ) .> getValue "name") patternoo
						ft1 = if ft1S == "Partial" then Partial else Total
						id1 = Hets.stringToId $ xshow $ applyXmlFilter (getChildren .> isTag "OMBIND" .> getChildren .> isTag "OMATTR" .> getChildren .> isTag "OMS" .> withValue "name" (/="result") .> getValue "name") patternoo
						parx = applyXmlFilter (getChildren .> isTag "OMBIND" .> getChildren .> isTag "OMBVAR" .> getChildren) patternoo
						par = foldl (\pl px ->
								pl ++ [Hets.stringToId $ xshow $ applyXmlFilter (isTag "OMATTR" .> getChildren .> isTag "OMATP" .> getChildren .> isTag "OMS" .> withValue "name" (/=typeS) .> getValue "name") [px]]
								) [] parx
						res = Hets.stringToId $ xshow $ applyXmlFilter (getChildren .> isTag "OMBIND" .> getChildren .> isTag "OMATTR" .> getChildren .> isTag "OMATP" .> getChildren .> withValue "name" (\s -> (s /= typeS && s /= "Partial" && s /= "Total")) .> getValue "name") patternoo
						ft2S = xshow $ applyXmlFilter (getChildren .> isTag "OMATTR" .> getChildren .> isTag "OMATP" .> getChildren .> isTag "OMS" .> withValue "name" ( \s -> (s == "Total" || s == "Partial")) .> getValue "name") valueoo
						ft2 = if ft2S == "Partial" then Partial else Total
						id2 = Hets.stringToId $ xshow $ applyXmlFilter (getChildren .> isTag "OMATTR" .> getChildren .> isTag "OMS" .> getValue "name") valueoo
					in
						(sm, Map.insert (id1, (OpType ft1 par res)) (id2, ft2) fm, pm)
			else
				error ("Cannot build maps with : \"" ++ xshow [x] ++ "\"")
			) (Map.empty, Map.empty, Map.empty) t
						
-- XMLTOLINKS END
{-
-- FETCHPROOFSTEPS BEGIN

{-
What are proof-steps ?
Proof-steps are just lists of Edges.
After reading in all nodes and all edges we can go to collect proof-steps
Just came to my mind :
	When fetching proof-steps I do not have to consider replacing the
	links before finishing everything, because Proof-Steps will not
	link to other proof-steps...
-}

-- This function extracts proof-steps from Xml using an already constructed
-- DGraph for Information
fetchProofSteps::Static.DevGraph.DGraph->HXT.XmlTrees->Static.DevGraph.DGraph
fetchProofSteps dg t = let	theories = applyXmlFilter (isTag "theory") t
		       in
		          -- fold the proofsteps into the DGraph
			  -- by theory
		       	  foldl (\newdg theory ->
			  		fetchProofStepsFor dg [theory] ) dg theories
					
-- after all these helpers lets get back to the problem
-- we are folding proof-steps into the DGraph for each theory, so this
-- function gets the current DGraph and an XmlTree containing the single theory
-- (so it fetches the proof-steps _for_ this theory...)
fetchProofStepsFor::Static.DevGraph.DGraph->HXT.XmlTrees->Static.DevGraph.DGraph
fetchProofStepsFor dg t = let	tnameS = xshow $ applyXmlFilter (getValue "id") t
				toNodeN = nodeNameToNodeNum (Graph.labNodes dg) tnameS
				importswithproofsteps = applyXmlFilter (getChildren .> (isTag "axiom-inclusion" +++ isTag "theory-inclusion")) t
				proofsteps = applyXmlFilter (getChildren .> isTag "proof-object") t
			  in
			    foldl (\newdg importx ->
			    		let	isLocalThm = applyXmlFilter (isTag "axiom-inclusion") [importx] /= []
						fromNameS = xshow $ applyXmlFilter (getValue "from") [importx]
						fromNodeN = nodeNameToNodeNum (Graph.labNodes dg) fromNameS
						(n, m, myedge) = getSpecialEdge (Graph.labEdges newdg) fromNodeN toNodeN (if isLocalThm then isLocalThmEdge else isGlobalThmEdge)
						-- every import has at most one proof-object...
						thisproofsteps = applyXmlFilter (withSValue "theory" fromNameS .> withSValue "for" tnameS) proofsteps
						(tls1, cons, tls2) = xmlToLinkStatus dg thisproofsteps
					in Graph.insEdge (n, m, (replaceThmLinkStati myedge (tls1, cons, tls2))) (Graph.delEdge (n,m) newdg)
					) dg importswithproofsteps

-}
-- Helper-function to get the Number of a Node in the DGraph given the Name
nodeNameToNodeNum::[Graph.LNode Static.DevGraph.DGNodeLab]->String->Graph.Node
nodeNameToNodeNum [] _ = error "no such node"
nodeNameToNodeNum ((n, node):rest) name' = if name' == (Static.DevGraph.getDGNodeName node) then n
						else nodeNameToNodeNum rest name'
		

-- we get into the problem to delete an edge wich may not be the only egde
-- between two nodes. So this function performs a test on a edge that
-- may fit the connection.
getSpecialEdge::[Graph.LEdge Static.DevGraph.DGLinkLab]->Graph.Node->Graph.Node->(Static.DevGraph.DGLinkLab->Bool)->(Graph.LEdge Static.DevGraph.DGLinkLab)
getSpecialEdge [] _ _ _ = error "no such special edge"
getSpecialEdge ((theedge@(n,m,edge)):rest) n' m' isSpecial = if ( n==n' ) && ( m == m' ) && (isSpecial edge) then theedge
								else getSpecialEdge rest n' m' isSpecial

-- externalized test-function for edges 								
isLocalThmEdge::Static.DevGraph.DGLinkLab->Bool
isLocalThmEdge (DGLink _ (LocalThm _ _ _) _) = True
isLocalThmEdge _ = False

-- externalized test-function for edges 								
isGlobalThmEdge::Static.DevGraph.DGLinkLab->Bool
isGlobalThmEdge (DGLink _ (GlobalThm _ _ _) _) = True
isGlobalThmEdge _ = False

-- this is a very clumsy yet simple way to change 'just' the Proof-Steps of
-- an edge (So I do not have to worry about Global/Local later).
replaceThmLinkStati::Static.DevGraph.DGLinkLab->(ThmLinkStatus, Conservativity, ThmLinkStatus)->Static.DevGraph.DGLinkLab
replaceThmLinkStati (DGLink a (LocalThm _ _ _) b) (tls1, c, tls2) = DGLink a (LocalThm tls1 c tls2) b
replaceThmLinkStati (DGLink a (GlobalThm _ _ _) b) (tls1, c, tls2) = DGLink a (GlobalThm tls1 c tls2) b
replaceThmLinkStati a _ = error ("Cannot replace ThmLinkStati on \"" ++ show a ++ "\"") 

-- to delete an edge, we have to find it first
-- this function finds an edge provided the two nodes connected (direction matters)
-- i think this function is not used
getEdgeByNodeNums::[Graph.LEdge Static.DevGraph.DGLinkLab]->Graph.Node->Graph.Node->(Graph.LEdge Static.DevGraph.DGLinkLab)
getEdgeByNodeNums [] _ _ = error "no such edge"
getEdgeByNodeNums ((theedge@(n,m,_)):rest) n' m' = if ( n==n' ) && ( m == m' ) then theedge
							else getEdgeByNodeNums rest n' m'

-- To create proof-steps, all Edges have to be already in the DG
xmlToProofSteps::HXT.XmlTrees->Static.DevGraph.DGraph->[Static.DevGraph.DGLinkLab]
xmlToProofSteps t dg = map (\n -> xmlToProofStep [n] dg) $ ((applyXmlFilter (isTag "OMSTR") t)::[XmlTree])

-- create a single proof-step (find an edge)
xmlToProofStep::HXT.XmlTrees->Static.DevGraph.DGraph->Static.DevGraph.DGLinkLab
xmlToProofStep t dg = let	n1ton2S = xshow $ applyXmlFilter (getChildren) t
				n1S = getStringBefore "->" n1ton2S
				n2S = drop ((length n1S) + (length "->")) n1ton2S
				labnodes = Graph.labNodes dg
				labedges = Graph.labEdges dg
				(Just n1Num) = findNodeNumFor labnodes n1S
				(Just n2Num) = findNodeNumFor labnodes n2S
				maybeEdge = findEdgeFor labedges n1Num n2Num
		      in case maybeEdge of
		      		(Just a) -> a
				Nothing -> error ("Cannot find Edge for \"" ++ xshow t ++ "\"")
				
-- another helper
getStringBefore::String->String->String
getStringBefore _ [] = []
getStringBefore sub (c:s) = if isPrefix sub (c:s) then []
			else [c] ++ (getStringBefore sub s)
-- helper function
isPrefix::String->String->Bool
isPrefix [] _ = True
isPrefix _ [] = False
isPrefix (p:p' ) (s:s' ) = (p == s) && (isPrefix p' s')

-- finds a nodeNumber by Name (maybe)
findNodeNumFor::[(Graph.LNode Static.DevGraph.DGNodeLab)]->String->(Maybe Graph.Node)
findNodeNumFor [] _ = Nothing
findNodeNumFor ((n, node):rest) name' = if (name' == Static.DevGraph.getDGNodeName node) then (Just n)
					else findNodeNumFor rest name'
-- finds an edge by node numbers (maybe)					
findEdgeFor::[(Graph.LEdge Static.DevGraph.DGLinkLab)]->Graph.Node->Graph.Node->(Maybe Static.DevGraph.DGLinkLab)
findEdgeFor [] _ _ = Nothing
findEdgeFor ((n1, n2, edge):rest) node1 node2 = if (node1==n1) && (node2==n2) then (Just edge)
							else findEdgeFor rest node1 node2
-- convert Xml to Conservativity
xmlToConservativity::HXT.XmlTrees->Static.DevGraph.Conservativity
xmlToConservativity t = if applyXmlFilter (isTag "OMSTR") t /= [] then
			  let conS = drop (length "Conservativity: ") (xshow $ applyXmlFilter (getChildren) t)
			  in
			  if conS == "None" then None
			  else
			  if conS == "Cons" then Cons
			  else
			  if conS == "Mono" then Mono
			  else
			  if conS == "Def" then Def
			  else
			    error ("Illegal Conservativity : \""++ conS ++"\"")
			else
			  error ("Cannot create Conservativity from \""++ xshow t ++"\"")
			  
-- FETCHPROOFSTEPS END

-- CLEANUP BEGIN
-- we need to clear the anonymous nodes after the whole graph creation
-- we needed the unique names to build the edges...

cleanup::Static.DevGraph.DGraph->Static.DevGraph.DGraph
cleanup dg =	let	labnodes = Graph.labNodes dg
			labedges = Graph.labEdges dg
			cleannodes = map (\(n,node) -> (n,cleannode node)) labnodes
		in Graph.mkGraph cleannodes labedges
		
cleannode::Static.DevGraph.DGNodeLab->Static.DevGraph.DGNodeLab
cleannode (Static.DevGraph.DGNode nam sgn arg sns nf sig org) = Static.DevGraph.DGNode (cleanname nam) sgn arg sns nf sig org  
cleannode (Static.DevGraph.DGRef nam ln n nt nf sig) = Static.DevGraph.DGRef (cleanname nam) ln n nt nf sig

cleanname::Static.DevGraph.NODE_NAME->Static.DevGraph.NODE_NAME
cleanname n = if isPrefix "anonnode:" (Static.DevGraph.showName n) then Static.DevGraph.emptyNodeName else n
		

-- CLEANUP END
			
{- I think the following functions are not used (anymore) -}

{-
To Create Edges we need to reparse theories while having already computed the
nodes. Because theories are refered to by their names we can build the real
edges by referring to the nodes (we need their signs...).
-}
fetchEdges::Static.DevGraph.DGraph->HXT.XmlTrees->Static.DevGraph.DGraph
fetchEdges dgwithnodes theories =
	-- each theorie can contain multiple imports from other theories (edges)
	let _ = map (\t -> let
			--(theoryName, imports, proofs) = getTheoryNameImportAndProof [t]
			(_, _, _) = getTheoryNameImportAndProof [t]
		   in Nothing ) theories
	in
	dgwithnodes	

-- to clear the code a bit	
validImports::HXT.XmlFilter
validImports = (isTag "imports" +++ isTag "axiom-inclusion" +++ isTag "theory-inclusion")

-- to clear the code a bit	
validProofs::HXT.XmlFilter
validProofs = (isTag "proofobject")

-- this function splits a theory-XmlTree into its name, imports and proof-steps
getTheoryNameImportAndProof::HXT.XmlTrees->(String, XmlTrees, XmlTrees)
getTheoryNameImportAndProof t = (
				 xshow $ applyXmlFilter (isTag "theory" .> getValue "id") t
				,applyXmlFilter (getChildren .> validImports) t
				,applyXmlFilter (getChildren .> validProofs) t
				)


{-
 DGRef's have (maybe) a Name but always a Library-Name and know the
 nodes number in the DG of that library.
 We have no node-numbers in our Xml-representation just unambigous names...
 we could make sure that nodes are ordered by their node number but what
 about human intervention ?
 perhaps we should save the number of a node into the xml or -- what i like
 better -- we should only support DGRef's with a name...
 A DGRef has no signature but we need a signature to construct the edges.
 Should these signatures be saved to Xml or should we assume, that there is
 always a way to receive the signature ?
 On the long run, the latter is the only choice, but this will make testing
 more complicated...
 On the other hand : if for each DGRef-Info in the Xml a new DGraph is
 generated a lot of problems just dissolve (and come back as FileIO)...
-} 

		

-- for some wierd reason, 'lab' from Graph can't be used...
-- I don't get it... this function is almost a copy...
lab :: Static.DevGraph.DGraph-> Graph.Node -> Maybe DGNodeLab
lab g v = fst (Graph.match v g) >>= return . Graph.lab' 


-- I don't think this function is really used or I have found something else
-- for processing inclusions...
xmlToLinkType::HXT.XmlTrees->Static.DevGraph.DGLinkType
xmlToLinkType t = if applyXmlFilter (isTag "imports") t /= [] then
		 let	ltypeS = xshow $ applyXmlFilter(getValue "type") t
		 in
		 if ltypeS == "local" then LocalDef
		 else
		 if ltypeS == "global" then GlobalDef
		 else
		 if ltypeS == "hiding" then HidingDef -- not in Omdoc...
		 else
		   error ("Illegal Import-type in : \""++ xshow t ++"\"")
	      else
	        error ("Cannot create Link-Type from : \""++ xshow t ++"\"")
			
posLines::[Id.Pos]->IO (Map.Map Id.Pos String)
posLines posl =
	do
		(psm, _) <- foldl (\iomaps pos@(Id.SourcePos name' line _) ->
			do
			(strmap, linemap) <- iomaps
			case Map.lookup name' linemap of
				(Just flines) ->
					return (Map.insert pos (headorempty (drop (line-1) flines)) strmap,
					 linemap)
				Nothing ->
					do
						fe <- System.Directory.doesFileExist name'
						f <- if fe then readFile name' else (return "")
						flines <- return (lines f)
						return (Map.insert pos (headorempty (drop (line-1) flines)) strmap,
							Map.insert name' flines linemap)
				) (return (Map.empty, Map.empty)) posl
		return psm
									
{-		iolines <- foldl
			(\lio (Id.SourcePos name _ _) ->
				lio >>= \l ->
					case Map.lookup name l of
						Nothing ->
							do
								newmap <- return (Map.insert
									name
									(
										do
											putStrLn (name ++ " not found in " ++ (show $ Map.keys l))
											fe <- System.Directory.doesFileExist name
											f <- if fe then readFile name else (return "")
											return $ lines f
									)
									l)
								putStrLn  ("New map : " ++ (show $ Map.keys l))
								return newmap
						(Just _) -> return l
				) (return (Map.empty::(Map.Map String (IO [String])))) posl
		foldl
			(\mio pos@(Id.SourcePos name linenum _) ->
				mio >>= \m -> 
					case Map.lookup name iolines of
						Nothing -> ioError (userError "This can not happen!")
						(Just lineio) ->
							lineio >>= \nline -> return (Map.insert pos ( headorempty $ drop (linenum-1) nline) m)
					) (return Map.empty) posl -}

-- FORMULAS -> X M L 

-- Above ends the part for creating DGraphs
-- No we enter the fascinating world of Formula-Processing... (22:58)

-- Formulas as OMA
-- wrap in Theory-axiom-FMP.

wrapFormulas::Hets.ImportsMap->Hets.SortsMap->Hets.PredsMap->Hets.OpsMap->String->[(Ann.Named CASLFORMULA)]->(HXT.XmlTree->HXT.XmlTrees)
wrapFormulas imports' sorts' preds' ops' name' fs = (\(a,_) -> a) $ foldl (\(wrapped, n) f -> (wrapped +++ (wrapFormula imports' sorts' preds' ops' name' n f), n+1) ) (HXT.txt "", 1) fs

wrapFormulasCMPIO::Hets.ImportsMap->Hets.SortsMap->Hets.PredsMap->Hets.OpsMap->String->[(Ann.Named CASLFORMULA)]->IO (HXT.XmlTree->HXT.XmlTrees)
wrapFormulasCMPIO imports' sorts' preds' ops' name' fs =
	let
		posLists = concatMap Id.getPosList (map Ann.sentence fs)
	in
	do
		poslinemap <- posLines posLists
		(\(a,_) -> return a) $ foldl (\(wrapped, n) f -> (wrapped +++ (wrapFormulaCMP imports' sorts' preds' ops' name' n f poslinemap), n+1) ) (HXT.txt "", 1) fs
		
wrapFormulasCMPIOXN::PFInput->[XmlNamedWON (Ann.Named CASLFORMULA)]->IO (HXT.XmlTree->HXT.XmlTrees)
wrapFormulasCMPIOXN pfinput fs =
	let
		posLists = concatMap Id.getPosList (map (Ann.sentence . xnWOaToa) fs)
	in
	do
		poslinemap <- posLines posLists
		return $ foldl (\wrapped f -> wrapped +++ (wrapFormulaCMPXN pfinput f poslinemap) ) (HXT.txt "") fs

wrapFormulaCMP::
	Hets.ImportsMap->
	Hets.SortsMap->
	Hets.PredsMap->
	Hets.OpsMap->
	String->
	Int->
	(Ann.Named CASLFORMULA)->
	(Map.Map Id.Pos String)->
	(HXT.XmlTree->HXT.XmlTrees)
wrapFormulaCMP
	imports'
	sorts'
	preds'
	ops'
	tname
	number
	ansen
	poslinemap =
	let
		sens = Ann.sentence ansen
		sposl = Id.getPosList sens
	in
	(
		(createQAttributed
			"axiom"
			[	(axiomNameXMLNS,
				axiomNameXMLAttr,
				let name' = (Ann.senName ansen) in
					if name' =="" then ("AnonAx"++(show number)) else name' )
			]
		) += (
			(xmlNL +++
			((foldl (\cmpx p -> cmpx += (HXT.txt ("\n" ++ (Map.findWithDefault "" p poslinemap))) ) (HXT.etag "CMP") sposl) += (HXT.txt "\n"))+++ 
			xmlNL +++
			(HXT.etag "FMP"	+= (
				xmlNL +++
				(
				 HXT.etag "OMOBJ" +++
				 xmlNL
				) += (
					xmlNL +++
					(processFormula
						imports'
						sorts'
						preds'
						ops'
						tname
						sens
					)
					) +++
				xmlNL
				)
			) +++
			xmlNL
			)
			)
	) +++ xmlNL
	
wrapFormulaCMPXN::
	PFInput->
	(XmlNamedWON (Ann.Named CASLFORMULA))->
	(Map.Map Id.Pos String)->
	(HXT.XmlTree->HXT.XmlTrees)
wrapFormulaCMPXN
	pfinput
	ansenxn
	poslinemap =
	let
		sens = Ann.sentence (xnWOaToa ansenxn)
		sposl = Id.getPosList sens
	in
	(
		(createQAttributed
			"axiom"
			[	(axiomNameXMLNS,
				axiomNameXMLAttr,
				(xnName ansenxn))
			]
		) += (
			(xmlNL +++
			((foldl (\cmpx p -> cmpx += (HXT.txt ("\n" ++ (Map.findWithDefault "" p poslinemap))) ) (HXT.etag "CMP") sposl) += (HXT.txt "\n"))+++ 
			xmlNL +++
			(HXT.etag "FMP"	+= (
				xmlNL +++
				(
				 HXT.etag "OMOBJ" +++
				 xmlNL
				) += (
					xmlNL +++
					(processFormulaXN
						pfinput
						sens
					)
					) +++
				xmlNL
				)
			) +++
			xmlNL
			)
			) +++
		xmlNL +++
		makePresentationFor (xnName ansenxn) (Ann.senName (xnWOaToa ansenxn))
	) +++ xmlNL

	
wrapFormula::
	Hets.ImportsMap->
	Hets.SortsMap->
	Hets.PredsMap->
	Hets.OpsMap->
	String->
	Int->
	(Ann.Named CASLFORMULA)->
	(HXT.XmlTree->HXT.XmlTrees)
wrapFormula
	imports'
	sorts'
	preds'
	ops'
	tname
	number
	ansen =
	let
		sens = Ann.sentence ansen
		sposl = Id.getPosList sens
	in
	(
		(createQAttributed
			"axiom"
			[	(axiomNameXMLNS,
				axiomNameXMLAttr,
				let name' = (Ann.senName ansen) in
					if name' =="" then ("AnonAx"++(show number)) else name' )
			]
		) += (
			(xmlNL +++
			(foldl (\cmpx p -> cmpx += (HXT.txt ((show p) ++ "\n")) ) (HXT.etag "CMP") sposl) +++ 
			xmlNL +++
			(HXT.etag "FMP"	+= (
				xmlNL +++
				(
				 HXT.etag "OMOBJ" +++
				 xmlNL
				) += (
					xmlNL +++
					(processFormula
						imports'
						sorts'
						preds'
						ops'
						tname
						sens
					)
					) +++
				xmlNL
				)
			) +++
			xmlNL
			)
			)
	) +++ xmlNL
	
-- shortcut to create an attribute with a qualified name (but no namespace uri)
-- leave prefix (p) blank to just have a normal attribute
qualattr::String->String->String->XmlFilter
qualattr p a v = HXT.qattr (HXT.mkPrefixLocalPart p a) (HXT.mkXText v)
--qualattr p a v = HXT.qattr (HXT.mkPrefixLocalPart "" a) (HXT.mkXText v)

-- creates a tag with qualified attributes (p,a,v) (no namespace uri)
createQAttributed::String->[(String,String,String)]->XmlFilter
createQAttributed tagname attributes =
	foldl (\tag' (p, a, v) -> tag' += qualattr p a v) (HXT.etag tagname) attributes
					
-- creates a tag with unqualified attributes (a,v)
createAttributed::String->[(String,String)]->XmlFilter
createAttributed tagname attributes =
	createQAttributed tagname $ map (\(a, v) -> ("", a, v) ) attributes
					
--caslS :: String -- moved to OmdocDevGraph
--typeS :: String

--caslQuantificationS
caslConjunctionS
	,caslDisjunctionS
	,caslImplicationS
	,caslImplication2S
	,caslEquivalenceS
	,caslEquivalence2S
	,caslNegationS
	,caslPredicationS
	,caslDefinednessS
	,caslExistl_equationS
	,caslStrong_equationS
	,caslMembershipS
	,caslSort_gen_axS :: String

caslSymbolQuantUniversalS
	,caslSymbolQuantExistentialS
	,caslSymbolQuantUnique_existentialS
	,caslSymbolAtomFalseS
	,caslSymbolAtomTrueS :: String


unsupportedS :: String

--caslS = "casl"
--typeS = "type"

--caslQuantificationS = "quantification"
caslConjunctionS = "conjunction"
caslDisjunctionS = "disjunction"
caslImplicationS = "implication"
caslImplication2S = "implies"
caslEquivalenceS = "equivalence"
caslEquivalence2S = "equal"
caslNegationS = "neg"
caslPredicationS = "predication"
caslDefinednessS = "definedness"
caslExistl_equationS = "existial-equation"
caslStrong_equationS = "strong-equation"
caslMembershipS = "membership"
caslSort_gen_axS = "sort-gen-ax"

caslSymbolQuantUniversalS = "universal"
caslSymbolQuantExistentialS = "existential"
caslSymbolQuantUnique_existentialS = "unique-existential"

caslSymbolAtomFalseS = "false"
caslSymbolAtomTrueS = "true"

unsupportedS = "unsupported-formula"


createSymbolForSort::Hets.ImportsMap->Hets.SortsMap->SORT->String->(HXT.XmlTree->HXT.XmlTrees)
createSymbolForSort imports' sorts' sort name' =
	HXT.etag "OMS" += ( HXT.sattr "cd" (fromMaybe "unknown" $ Hets.findNodeNameForSort imports' sorts' sort name' ) +++ HXT.sattr "name" (show sort) )

createSymbolForSortXN::TheoryXNSet->XmlNamedWONSORT->(HXT.XmlTree->HXT.XmlTrees)
createSymbolForSortXN theoryset xnsort =
	HXT.etag "OMS" += ( HXT.sattr "cd" (fromMaybe "unknown" $ getTheoryXmlName theoryset (xnWOaToO xnsort) ) +++ HXT.sattr "name" (xnName xnsort) )
	
createSymbolForSortWithSortXNSet::TheoryXNSet->Set.Set XmlNamedWONSORT->SORT->HXT.XmlFilter
createSymbolForSortWithSortXNSet theoryset theorysorts sort =
	let
		xnsort = case sortToXmlNamedWONSORTSet theorysorts sort of
			Nothing -> error "Cannot create the Symbol because I cannot find the Sort !"
			(Just xnsort' ) -> xnsort'
	in
		createSymbolForSortXN theoryset xnsort
	
-- | create the xml-representation for a formula (in context of a theory)	
processFormula ::
	Hets.ImportsMap-> -- ^ the map of imports
	Hets.SortsMap-> -- ^ the map of sorts
	Hets.PredsMap-> -- ^ the map of predications
	Hets.OpsMap-> -- ^ the map of operators
	String-> -- ^ the name of the current theory
	(FORMULA f)-> -- ^ the formula to process
	(HXT.XmlTree->HXT.XmlTrees) -- ^ a xml-representation of the formula
-- Quantification
processFormula imports' sorts' preds' ops' name'
	(Quantification q vl f _) =
		( HXT.etag "OMBIND" += (
			xmlNL +++
			(HXT.etag "OMS" +=
				(HXT.sattr "cd" caslS +++
				HXT.sattr "name" (quantName q))
			) +++
			(xmlNL) +++
			(processVarDecl imports' sorts' name' vl) +++
			(processFormula imports' sorts' preds' ops' name' f) )
		) +++
		xmlNL
-- Conjunction
processFormula imports' sorts' preds' ops' name'
	(Conjunction fl _) =
		(HXT.etag "OMA" += (
			xmlNL +++
			( HXT.etag "OMS" +=
				(HXT.sattr "cd" caslS +++
				HXT.sattr "name" caslConjunctionS)
			) +++
			(foldl (\forms f ->
				forms +++
				processFormula imports' sorts' preds' ops' name' f
				) (xmlNL) fl)
		) ) +++
		xmlNL
-- Disjunction
processFormula imports' sorts' preds' ops' name'
	(Disjunction fl _) =
		(HXT.etag "OMA" += (
			xmlNL +++
			( HXT.etag "OMS" +=
				(HXT.sattr "cd" caslS +++
				HXT.sattr "name" caslDisjunctionS)
			) +++
			(foldl (\forms f ->
				forms +++
				processFormula imports' sorts' preds' ops' name' f
				) (xmlNL) fl)
		) ) +++
		xmlNL
-- Implication
processFormula imports' sorts' preds' ops' name'
	(Implication f1 f2 b _) =
		( HXT.etag "OMA" += (
			xmlNL +++
			( HXT.etag "OMS" +=
				(HXT.sattr "cd" caslS +++
				HXT.sattr "name" caslImplicationS)
			) +++
			(xmlNL) +++
			(processFormula imports' sorts' preds' ops' name' f1) +++
			(processFormula imports' sorts' preds' ops' name' f2) +++
			(processFormula imports' sorts' preds' ops' name'
				(if b then True_atom Id.nullRange else False_atom Id.nullRange))
		) ) +++
		xmlNL
-- Equivalence
processFormula imports' sorts' preds' ops' name'
	(Equivalence f1 f2 _) =
		( HXT.etag "OMA" += (
			xmlNL +++
			( HXT.etag "OMS" +=
				(HXT.sattr "cd" caslS +++
				HXT.sattr "name" caslEquivalenceS)
			) +++
			(xmlNL) +++
			(processFormula imports' sorts' preds' ops' name' f1) +++
			(processFormula imports' sorts' preds' ops' name' f2)
		) ) +++
		xmlNL
-- Negation
processFormula imports' sorts' preds' ops' name'
	(Negation f _) =
		( HXT.etag "OMA" += (
			xmlNL +++
			( HXT.etag "OMS" +=
				(HXT.sattr "cd" caslS +++
				HXT.sattr "name" caslNegationS)
			) +++
			(xmlNL) +++
			(processFormula imports' sorts' preds' ops' name' f)
		) ) +++
		xmlNL
-- Predication
processFormula imports' sorts' preds' ops' name'
	(Predication p tl _) =
		(HXT.etag "OMA" += (
			xmlNL +++
			(HXT.etag "OMS" +=
				(HXT.sattr "cd" caslS +++
				HXT.sattr "name" caslPredicationS)
			) +++
			xmlNL +++
			(xmlNL) +++
			(createSymbolForPredication imports' preds' name' p) +++
			(foldl (\term t ->
				term +++
				(processTerm imports' sorts' preds' ops' name' t) +++
				xmlNL
				) (HXT.txt "") tl
			) +++
			(xmlNL)
		) ) +++
		xmlNL
-- Definedness
processFormula imports' sorts' preds' ops' name'
	(Definedness t _ ) =
		(HXT.etag "OMA" += (
			xmlNL +++
			( HXT.etag "OMS" +=
				(HXT.sattr "cd" caslS +++
				HXT.sattr "name" caslDefinednessS)
			) +++
			(xmlNL) +++
			(processTerm imports' sorts' preds' ops' name' t)
		) ) +++
		xmlNL
-- Existl_equation
processFormula imports' sorts' preds' ops' name'
	(Existl_equation t1 t2 _) = 
		( HXT.etag "OMA" += (
			xmlNL +++
			( HXT.etag "OMS" +=
				(HXT.sattr "cd" caslS +++
				HXT.sattr "name" caslExistl_equationS)
			) +++
			(xmlNL) +++
			(processTerm imports' sorts' preds' ops' name' t1) +++
			(processTerm imports' sorts' preds' ops' name' t2)
		) ) +++
		xmlNL
-- Strong_equation
processFormula imports' sorts' preds' ops' name'
	(Strong_equation t1 t2 _) = 
		( HXT.etag "OMA" += (
			xmlNL +++
			( HXT.etag "OMS" +=
				(HXT.sattr "cd" caslS +++
				HXT.sattr "name" caslStrong_equationS)
			) +++
			(xmlNL) +++
			(processTerm imports' sorts' preds' ops' name' t1) +++
			(processTerm imports' sorts' preds' ops' name' t2)
		) ) +++
		xmlNL
-- Membership
processFormula imports' sorts' preds' ops' name'
	(Membership t s _) = 
		( HXT.etag "OMA" += (
			xmlNL +++
			( HXT.etag "OMS" +=
				(HXT.sattr "cd" caslS +++
				HXT.sattr "name" caslMembershipS)
			) +++
			(xmlNL) +++
			(processTerm imports' sorts' preds' ops' name' t) +++
			(createSymbolForSort imports' sorts' s name' )
		) ) +++
		xmlNL
-- False_atom
processFormula _ _ _ _ _
	(False_atom _) =
		(HXT.etag "OMS" +=
			(HXT.sattr "cd" caslS +++
			HXT.sattr "name" caslSymbolAtomFalseS)
		) +++
		xmlNL
-- True_atom
processFormula _ _ _ _ _
	(True_atom _) =
		(HXT.etag "OMS" +=
			(HXT.sattr "cd" caslS +++
			HXT.sattr "name" caslSymbolAtomTrueS)
		) +++
		xmlNL
-- Sort_gen_ax
processFormula imports' _ _ ops' name'
	(Sort_gen_ax constraints freetype) =
		( HXT.etag "OMA" +=
			(xmlNL +++
			( HXT.etag "OMS" +=
				(HXT.sattr "cd" caslS +++
				HXT.sattr "name" caslSort_gen_axS)
			) +++
			(xmlNL) +++
			--(HXT.etag "OMBVAR" += -- ombvar not allowed in oma
			--	( xmlNL +++
				(processConstraints imports' ops' name' constraints) +++
			--	)
			--) +++
			HXT.etag "OMS" +=
				(HXT.sattr "cd" caslS +++
				HXT.sattr "name"
					(if freetype then
							caslSymbolAtomTrueS
						else
							caslSymbolAtomFalseS)
				) +++
				xmlNL
			) +++
			xmlNL) +++
			xmlNL
-- unsupported formulas
-- Mixfix_formula
processFormula _ _ _ _ _
	(Mixfix_formula _) =
		HXT.etag unsupportedS +++
		HXT.txt ( "<-- " ++ "Mixfix_formula" ++ " //-->")
-- Unparsed_formula
processFormula _ _ _ _ _
	(Unparsed_formula s _) =
		HXT.etag unsupportedS +++
		HXT.txt ( "<-- " ++ "Unparsed_formula \"" ++ s ++ "\" //-->")
-- ExtFORMULA
processFormula _ _ _ _ _
	(ExtFORMULA _) =
		HXT.etag unsupportedS +++
		HXT.txt ( "<-- " ++ "ExtFORMULA" ++ " //-->")
		
data PFInput = PFInput 	{	 theorySet::TheoryXNSet
							,theorySorts::Set.Set XmlNamedWONSORT
							,theoryPreds::[(XmlNamedWONId, PredTypeXNWON)]
							,theoryOps::[(XmlNamedWONId, OpTypeXNWON)]
						}
		
-- | create the xml-representation for a formula (in context of a theory)	
processFormulaXN ::
	PFInput->
	(FORMULA f)-> -- ^ the formula to process
	(HXT.XmlTree->HXT.XmlTrees) -- ^ a xml-representation of the formula
-- Quantification
processFormulaXN pfinput 
	(Quantification q vl f _) =
		( HXT.etag "OMBIND" += (
			xmlNL +++
			(HXT.etag "OMS" +=
				(HXT.sattr "cd" caslS +++
				HXT.sattr "name" (quantName q))
			) +++
			(xmlNL) +++
			(processVarDeclXN (theorySet pfinput) (theorySorts pfinput) vl) +++
			(processFormulaXN pfinput f) )
		) +++
		xmlNL
-- Conjunction
processFormulaXN pfinput
	(Conjunction fl _) =
		(HXT.etag "OMA" += (
			xmlNL +++
			( HXT.etag "OMS" +=
				(HXT.sattr "cd" caslS +++
				HXT.sattr "name" caslConjunctionS)
			) +++
			(foldl (\forms f ->
				forms +++
				processFormulaXN pfinput f
				) (xmlNL) fl)
		) ) +++
		xmlNL
-- Disjunction
processFormulaXN pfinput
	(Disjunction fl _) =
		(HXT.etag "OMA" += (
			xmlNL +++
			( HXT.etag "OMS" +=
				(HXT.sattr "cd" caslS +++
				HXT.sattr "name" caslDisjunctionS)
			) +++
			(foldl (\forms f ->
				forms +++
				processFormulaXN pfinput f
				) (xmlNL) fl)
		) ) +++
		xmlNL
-- Implication
processFormulaXN pfinput
	(Implication f1 f2 b _) =
		( HXT.etag "OMA" += (
			xmlNL +++
			( HXT.etag "OMS" +=
				(HXT.sattr "cd" caslS +++
				HXT.sattr "name" caslImplicationS)
			) +++
			(xmlNL) +++
			(processFormulaXN pfinput f1) +++
			(processFormulaXN pfinput f2) +++
			(processFormulaXN pfinput
				(if b then True_atom Id.nullRange else False_atom Id.nullRange))
		) ) +++
		xmlNL
-- Equivalence
processFormulaXN pfinput
	(Equivalence f1 f2 _) =
		( HXT.etag "OMA" += (
			xmlNL +++
			( HXT.etag "OMS" +=
				(HXT.sattr "cd" caslS +++
				HXT.sattr "name" caslEquivalenceS)
			) +++
			(xmlNL) +++
			(processFormulaXN pfinput f1) +++
			(processFormulaXN pfinput f2)
		) ) +++
		xmlNL
-- Negation
processFormulaXN pfinput
	(Negation f _) =
		( HXT.etag "OMA" += (
			xmlNL +++
			( HXT.etag "OMS" +=
				(HXT.sattr "cd" caslS +++
				HXT.sattr "name" caslNegationS)
			) +++
			(xmlNL) +++
			(processFormulaXN pfinput f)
		) ) +++
		xmlNL
-- Predication
processFormulaXN pfinput
	(Predication p tl _) =
		(HXT.etag "OMA" += (
			xmlNL +++
			(HXT.etag "OMS" +=
				(HXT.sattr "cd" caslS +++
				HXT.sattr "name" caslPredicationS)
			) +++
			xmlNL +++
			(xmlNL) +++
			(createSymbolForPredicationXN (theorySet pfinput) (theoryPreds pfinput) p) +++
			(foldl (\term t ->
				term +++
				(processTermXN pfinput t) +++
				xmlNL
				) (HXT.txt "") tl
			) +++
			(xmlNL)
		) ) +++
		xmlNL
-- Definedness
processFormulaXN pfinput
	(Definedness t _ ) =
		(HXT.etag "OMA" += (
			xmlNL +++
			( HXT.etag "OMS" +=
				(HXT.sattr "cd" caslS +++
				HXT.sattr "name" caslDefinednessS)
			) +++
			(xmlNL) +++
			(processTermXN pfinput t)
		) ) +++
		xmlNL
-- Existl_equation
processFormulaXN pfinput
	(Existl_equation t1 t2 _) = 
		( HXT.etag "OMA" += (
			xmlNL +++
			( HXT.etag "OMS" +=
				(HXT.sattr "cd" caslS +++
				HXT.sattr "name" caslExistl_equationS)
			) +++
			(xmlNL) +++
			(processTermXN pfinput t1) +++
			(processTermXN pfinput t2)
		) ) +++
		xmlNL
-- Strong_equation
processFormulaXN pfinput
	(Strong_equation t1 t2 _) = 
		( HXT.etag "OMA" += (
			xmlNL +++
			( HXT.etag "OMS" +=
				(HXT.sattr "cd" caslS +++
				HXT.sattr "name" caslStrong_equationS)
			) +++
			(xmlNL) +++
			(processTermXN pfinput t1) +++
			(processTermXN pfinput t2)
		) ) +++
		xmlNL
-- Membership
processFormulaXN pfinput
	(Membership t s _) = 
		( HXT.etag "OMA" += (
			xmlNL +++
			( HXT.etag "OMS" +=
				(HXT.sattr "cd" caslS +++
				HXT.sattr "name" caslMembershipS)
			) +++
			(xmlNL) +++
			(processTermXN pfinput t) +++
			(createSymbolForSortWithSortXNSet (theorySet pfinput) (theorySorts pfinput) s )
		) ) +++
		xmlNL
-- False_atom
processFormulaXN _
	(False_atom _) =
		(HXT.etag "OMS" +=
			(HXT.sattr "cd" caslS +++
			HXT.sattr "name" caslSymbolAtomFalseS)
		) +++
		xmlNL
-- True_atom
processFormulaXN _
	(True_atom _) =
		(HXT.etag "OMS" +=
			(HXT.sattr "cd" caslS +++
			HXT.sattr "name" caslSymbolAtomTrueS)
		) +++
		xmlNL
-- Sort_gen_ax
processFormulaXN pfinput
	(Sort_gen_ax constraints freetype) =
		( HXT.etag "OMA" +=
			(xmlNL +++
			( HXT.etag "OMS" +=
				(HXT.sattr "cd" caslS +++
				HXT.sattr "name" caslSort_gen_axS)
			) +++
			(xmlNL) +++
			--(HXT.etag "OMBVAR" += -- ombvar not allowed in oma
			--	( xmlNL +++
				(processConstraintsXN pfinput constraints) +++
			--	)
			--) +++
			HXT.etag "OMS" +=
				(HXT.sattr "cd" caslS +++
				HXT.sattr "name"
					(if freetype then
							caslSymbolAtomTrueS
						else
							caslSymbolAtomFalseS)
				) +++
				xmlNL
			) +++
			xmlNL) +++
			xmlNL
-- unsupported formulas
-- Mixfix_formula
processFormulaXN _
	(Mixfix_formula _) =
		HXT.etag unsupportedS +++
		HXT.txt ( "<-- " ++ "Mixfix_formula" ++ " //-->")
-- Unparsed_formula
processFormulaXN _
	(Unparsed_formula s _) =
		HXT.etag unsupportedS +++
		HXT.txt ( "<-- " ++ "Unparsed_formula \"" ++ s ++ "\" //-->")
-- ExtFORMULA
processFormulaXN _
	(ExtFORMULA _) =
		HXT.etag unsupportedS +++
		HXT.txt ( "<-- " ++ "ExtFORMULA" ++ " //-->") 

-- | create an xml-representation for a predication
createSymbolForPredication::
	Hets.ImportsMap-> -- ^ the map of imports
	Hets.PredsMap-> -- ^ the map of predication
	String-> -- ^ the name of the current theory
	PRED_SYMB-> -- ^ the predication to process
	(XmlTree->XmlTrees) -- ^ a xml-representation of the predication
-- Pred_name
createSymbolForPredication imports' preds' name'
	(Pred_name pr) =
		HXT.etag "OMS" +=
			(HXT.sattr "cd" (fromMaybe "unknown" $
				Hets.findNodeNameForPredication imports' preds' pr name' ) +++
			HXT.sattr "name" (show pr)
			)
-- Qual_pred_name
createSymbolForPredication imports' preds' name'
	(Qual_pred_name pr pt@(Pred_type args _) _) =
		HXT.etag "OMATTR" +=
			(xmlNL +++
			HXT.etag "OMATP" +=
				(xmlNL +++
				HXT.etag "OMS" +=
					(HXT.sattr "cd" "casl" +++ HXT.sattr "name" "type") +++
				xmlNL +++
				(HXT.etag "OMSTR" +=
					HXT.txt
						( (foldl
							(\t s -> t ++ "-\\" ++ (show s))
							(if args == [] then "" else (show $ head args))
							(drop 1 args)
						   )
						)
				)
				) +++
				xmlNL
			+++ -- symbol was left out of omattr... need to check back-conversion
			xmlNL +++
			HXT.etag "OMS" +=
				( HXT.sattr "cd" ( fromMaybe "unknown" $
					Hets.findNodeNameForPredicationWithSorts
						imports'	
						preds'
						(pr, cv_Pred_typeToPredType pt)
						name' ) +++
				HXT.sattr "name" (show pr)
				) +++
			xmlNL
		)
		
-- | create an xml-representation for a predication
createSymbolForPredicationXN::
	TheoryXNSet->
	[(XmlNamedWONId, PredTypeXNWON)]->
	PRED_SYMB-> -- ^ the predication to process
	(XmlTree->XmlTrees) -- ^ a xml-representation of the predication
-- Pred_name
createSymbolForPredicationXN theoryset theorypreds
	(Pred_name pr) =
		let
			(xnpid, _) = case find (\(xnpid' , _) ->
				(xnWOaToa xnpid' ) == pr ) theorypreds of 
					Nothing -> error "Cannot find predicate in theory!"
					(Just x' ) -> x'
		in
			HXT.etag "OMS" += 
				(HXT.sattr "cd" (fromMaybe "unknown" $
					getTheoryXmlName theoryset (xnWOaToO xnpid)) +++
				HXT.sattr "name" (xnName xnpid)
				)
-- Qual_pred_name
createSymbolForPredicationXN theoryset theorypreds
	(Qual_pred_name pr pt _) =
		let
			(xnpid, _) = case find (\(xnpid' , xnpt' ) ->
				(xnWOaToa xnpid' ) == pr &&
				(cv_PredTypeToPred_type $ predTypeXNWONToPredType xnpt' ) == pt ) theorypreds of
					Nothing -> error "Cannot find predicate in theory!"
					(Just x' ) -> x'
		in
			HXT.etag "OMS" +=
				( HXT.sattr "cd" ( fromMaybe "unknown" $
					getTheoryXmlName theoryset (xnWOaToO xnpid)
					) +++
				HXT.sattr "name" (xnName xnpid)
				) +++
			xmlNL


--data QUANTIFIER = Universal | Existential | Unique_existential
-- Quantifier as CASL Symbol
quantName :: QUANTIFIER->String
quantName Universal = caslSymbolQuantUniversalS
quantName Existential = caslSymbolQuantExistentialS
quantName Unique_existential = caslSymbolQuantUnique_existentialS

processConstraints::Hets.ImportsMap->Hets.OpsMap->String->[ABC.Constraint]->(HXT.XmlTree->HXT.XmlTrees)
processConstraints _ _ _ [] = HXT.txt ""
processConstraints importsmap opsmap name' ((ABC.Constraint news ops' origs):_) =
	(HXT.etag "OMBIND" += (
		(HXT.etag "OMS" += (HXT.sattr "cd" caslS +++ HXT.sattr "name" (show news)))
		+++ xmlNL
		+++ (HXT.etag "OMBVAR" +=(
			foldl (\opsx (op, il) ->
				opsx +++ (HXT.etag "OMATTR" += (
					(HXT.etag "OMATP" += (
						HXT.etag "OMS" += (HXT.sattr "cd" caslS +++ HXT.sattr "name" "constraint-indices")
						+++ (HXT.etag "OMSTR" += HXT.txt (
							foldl (\s i -> (s++(show i)++"|")) "" il
							))
						))
					+++ xmlNL
					+++ processOperator importsmap opsmap name' op
					) ) +++ xmlNL
				) (HXT.txt "") ops'
			) )
		+++ xmlNL
		+++ (HXT.etag "OMS" += (HXT.sattr "cd" caslS +++ HXT.sattr "name" (show origs))))) +++ xmlNL
		
-- need to check if this is correct with Xml --
processConstraintsXN::PFInput->[ABC.Constraint]->(HXT.XmlTree->HXT.XmlTrees)
processConstraintsXN _ [] = HXT.txt ""
processConstraintsXN pfinput ((ABC.Constraint news ops' origs):_) =
	(HXT.etag "OMBIND" += (
		(HXT.etag "OMS" += (HXT.sattr "cd" caslS +++ HXT.sattr "name" (show news)))
		+++ xmlNL
		+++ (HXT.etag "OMBVAR" +=(
			foldl (\opsx (op, il) ->
				opsx +++ (HXT.etag "OMATTR" += (
					(HXT.etag "OMATP" += (
						HXT.etag "OMS" += (HXT.sattr "cd" caslS +++ HXT.sattr "name" "constraint-indices")
						+++ (HXT.etag "OMSTR" += HXT.txt (
							foldl (\s i -> (s++(show i)++"|")) "" il
							))
						))
					+++ xmlNL
					+++ processOperatorXN pfinput op
					) ) +++ xmlNL
				) (HXT.txt "") ops'
			) )
		+++ xmlNL
		+++ (HXT.etag "OMS" += (HXT.sattr "cd" caslS +++ HXT.sattr "name" (show origs))))) +++ xmlNL

pairsToWhatIWant::Eq a=>[(a,a)]->[(a,[a])]
pairsToWhatIWant = foldl (\i x -> insert x i) [] where 
	insert::(Eq a, Eq b)=>(a,b)->[(a,[b])]->[(a,[b])]
	insert (a,b) [] = [(a,[b])]
	insert (a,b) ((a' ,l):r) = if a == a' then (a' , l++[b]):r else (a', l): insert (a,b) r
	
isTrueAtom::(FORMULA ())->Bool
isTrueAtom (True_atom _) = True
isTrueAtom _ = False

-- X M L -> FORMULA

unwrapFormulas::FormulaContext->HXT.XmlTrees->[(Ann.Named CASLFORMULA)]
unwrapFormulas fc t = map (\n -> unwrapFormula fc [n]) $ ((applyXmlFilter (isTag "axiom") t)::[XmlTree])

adjustFormulaName::String->String
adjustFormulaName s =
	if isPrefixOf "AnonAx" s then "" else
		s

data FormulaContext = FC {
	 imports :: Hets.ImportsMap
	,sorts :: Hets.SortsMap
	,rels :: Hets.RelsMap
	,preds :: Hets.PredsMap
	,ops :: Hets.OpsMap
	,currentName :: String
	}
	
emptyFormulaContext::FormulaContext
emptyFormulaContext = FC Map.empty Map.empty Map.empty Map.empty Map.empty ""
		
unwrapFormula::FormulaContext->HXT.XmlTrees->(Ann.Named CASLFORMULA)
unwrapFormula fc t =
	let
		name' = xshow $ applyXmlFilter (getQualValue axiomNameXMLNS axiomNameXMLAttr) t
		formtree = applyXmlFilter (getChildren .> isTag "FMP" .> getChildren .> isTag "OMOBJ" .> getChildren) t
	in
		Ann.NamedSen (adjustFormulaName name' ) True False (formulaFromXml fc formtree)

		  
tailorempty::[a]->[a]
tailorempty [] = []
tailorempty l = tail l

lastorempty::[a]->[a]
lastorempty [] = []
lastorempty l = [last l]

data FFXInput = FFXInput {
	xnTheorySet :: TheoryXNSet
	,xnSortSet :: Set.Set XmlNamedWONSORT
	,xnRelSet :: Rel.Rel XmlNamedWONSORT
	,xnPredMap :: Map.Map XmlName (Set.Set PredTypeXNWON)
	,xnOpMap :: Map.Map XmlName (Map.Map XmlNamedWONId (Set.Set OpTypeXNWON))
	}

formulaFromXml::FormulaContext->(HXT.XmlTrees)->(FORMULA ())
formulaFromXml fc t = if (applyXmlFilter (isTag "OMBIND") t) /= [] then -- it's a quantifier...
			let	quantTree = singleitem 1 (applyXmlFilter (isTag "OMBIND") t)
				quant = quantFromName $ xshow $ applyXmlFilter (getChildren .> isTag "OMS" .> withSValue "cd" caslS .> getValue "name") quantTree
				-- first element is the quantification-OMS
				formula = drop 1 ((applyXmlFilter (getChildren .> (isTag "OMA" +++ isTag "OMATTR" +++ isTag "OMBIND" +++ isTag "OMS")) quantTree)::[XmlTree]) 
				vardeclS = getVarDecls (applyXmlFilter (getChildren .> isTag "OMBVAR") quantTree)
				vardeclS2 = pairsToWhatIWant vardeclS
			in
				Quantification quant (map (\(s, vl) -> Var_decl (map Hets.stringToSimpleId vl) (Hets.stringToId s) Id.nullRange) vardeclS2) (formulaFromXml fc formula) Id.nullRange
			else if (applyXmlFilter (isTag "OMA") t) /= [] then -- the case begins...
			  let
			  	formTree = applyXmlFilter (isTag "OMA") t
				applySymXml = singleitem 1 (applyXmlFilter (getChildren .> isTag "OMS") formTree)
				applySym = xshow $ applyXmlFilter (getValue "name") applySymXml
				applySymCD = xshow $ applyXmlFilter (getValue "cd") applySymXml
			  in
				let	formulas = map (\n -> formulaFromXml fc [n]) ((applyXmlFilter (getChildren .> (isTag "OMA" +++ isTag "OMATTR" +++ isTag "OMBIND")) formTree)::[XmlTree])
					terms = map (\n -> termFromXml fc [n]) ((applyXmlFilter (getChildren .> (isTag "OMV" +++ isTag "OMATTR" +++ isTag "OMA")) formTree)::[XmlTree])
				in
				-- 'case applySym' does not work if case-strings are non fixed (above definition is not fixed enough...) 
			  	--case applySym of
					if applySym == caslConjunctionS then
						Conjunction formulas Id.nullRange
					else
					if applySym == caslDisjunctionS then
						Disjunction formulas Id.nullRange
					else
					if applySym `elem` [caslImplicationS, caslImplication2S] then
						let
							boolF = formulaFromXml fc (applyXmlFilter (processChildren (isTag "OMS") .> getChild 1) formTree) 
						in
							if (length formulas) < 2
								then
									Debug.Trace.trace ("Impossible to create implication...") (False_atom Id.nullRange)
								else
									Implication (formulas!!0) (formulas!!1) (isTrueAtom(boolF)) Id.nullRange
					else
					if applySym `elem` [caslEquivalenceS, caslEquivalence2S] then
						if (length formulas) < 2
							then
								Debug.Trace.trace ("Impossible to create equivalence...") (False_atom Id.nullRange)
							else
								Equivalence (formulas!!0) (formulas!!1) Id.nullRange
					else
					if applySym == caslNegationS then
						if formulas == []
							then
								Debug.Trace.trace ("Impossible to create negation...") (False_atom Id.nullRange)
							else
								Negation (formulas!!0) Id.nullRange
					else
					if applySym == caslPredicationS then
						let
							predxml = applyXmlFilter (processChildren (isTag "OMS" +++ isTag "OMATTR") .> getChild 1) t
							pred' = predicationFromXml predxml
							termxml = (applyXmlFilter (getChildren .> (isTag "OMATTR" +++ isTag "OMA")) t)
							predterms = map (\tx -> termFromXml fc [tx]) $ tailorempty termxml
						in
						if predxml == []
							then
								Debug.Trace.trace ("Impossible to create predication...") (False_atom Id.nullRange)
							else
								Predication pred' predterms Id.nullRange 
					else
					if applySym == caslDefinednessS then
						Definedness (termFromXml fc (applyXmlFilter (getChildren .> (isTag "OMV" +++ isTag "OMATTR" +++ isTag "OMA" )) t)) Id.nullRange
					else
					if applySym == caslExistl_equationS then
						if (length terms) < 2
							then
								Debug.Trace.trace ("Impossible to create existl_equation...") (False_atom Id.nullRange)
							else
								Existl_equation (terms!!0) (terms!!1) Id.nullRange
					else
					if applySym == caslStrong_equationS then
						if (length terms) < 2
							then
								Debug.Trace.trace ("Impossible to create strong_equation...") (False_atom Id.nullRange)
							else
								Strong_equation (terms!!0) (terms!!1) Id.nullRange
					else
					if applySym == caslMembershipS then
						let	sort = xshow $ lastorempty (applyXmlFilter (getChildren .> isTag "OMS" .> getValue "name") formTree)
						in
						if terms == []
							then
								Debug.Trace.trace ("Impossible to create Membership...") (False_atom Id.nullRange)
							else
								Membership (head terms) (Hets.stringToId sort) Id.nullRange
					else
					if applySym == caslSort_gen_axS then
						let	freeType = if (xshow $ applyXmlFilter (getValue "name") [(applyXmlFilter (getChildren .> isTag "OMS") formTree)!!1]) == caslSymbolAtomFalseS then False else True
							constraintsx = applyXmlFilter
								(
								--getChildren .> isTag "OMBVAR" .> -- removed (see generation)
								getChildren .> isTag "OMBIND"
								) formTree
							constraints = xmlToConstraints constraintsx
						in
						Sort_gen_ax constraints freeType
					else
--					if applySym /= [] then
						Debug.Trace.trace ("No matching casl-application found! Trying to find predicate...") $
							let
								-- try to find the node for this predicate
								mprednodename = Hets.findNodeNameForPredication (imports fc) (preds fc) (Hets.stringToId applySym) (currentName fc)
								predsMap' = case mprednodename of
									-- try to get predicate set via CD
									Nothing -> Map.findWithDefault (Debug.Trace.trace ("No Node found by CD...") Map.empty) applySymCD (preds fc)
									-- try to get predicate map from the node
									(Just prednodename) -> Map.findWithDefault (Debug.Trace.trace ("Node should contain predicate, but does not...") Map.empty) prednodename (preds fc)
								-- try to find the predicate set from the map
								mptset = Map.lookup (Hets.stringToId applySym) predsMap' :: (Maybe (Set.Set PredType))
								-- terms to apply predication to...
								predterms = map (\n -> termFromXml fc [n]) $ tail $ ((applyXmlFilter (getChildren .> (isTag "OMATTR" +++ isTag "OMA")) t)::[XmlTree])
							in
								case mptset of
									Nothing -> Debug.Trace.trace ("Could not find Predication for \"" ++ applySym ++ "\" from \"" ++ applySymCD ++ "\"") (False_atom Id.nullRange) -- error ("Could not find Predication for \"" ++ applySym ++ "\" from \"" ++ applySymCD ++ "\"")
									(Just ptset) ->
										if Set.null ptset
											then
												error ("Found mapping for predication \"" ++ applySym ++ "\" but no actual values... this is odd!")
											else
												Predication (Qual_pred_name (Hets.stringToId applySym) (cv_PredTypeToPred_type $ head $ Set.toList ptset) Id.nullRange) predterms Id.nullRange
--					else
--						error ("Expected a casl application symbol, but \"" ++ applySym ++ "\" was found!")
			  else if (applyXmlFilter (isTag "OMS") t) /= [] then
			  	let trueOrFalse = xshow $ singleitem 1 (applyXmlFilter (isTag "OMS" .> withSValue "cd" caslS .> getValue "name") t)
				in
				if trueOrFalse == caslSymbolAtomTrueS then
					True_atom Id.nullRange
					else
						if trueOrFalse == caslSymbolAtomFalseS then
							False_atom Id.nullRange
							else
								Debug.Trace.trace (caslSymbolAtomTrueS ++ " or " ++ caslSymbolAtomFalseS ++ " expected, but \"" ++ trueOrFalse ++ "\" found!") (False_atom Id.nullRange)
			  else
			  	error ("Impossible to create formula from \"" ++ xshow t++ "\"") 



xmlToConstraints::HXT.XmlTrees->[ABC.Constraint]
xmlToConstraints t =
	map (\n -> xmlToConstraint [n]) $ ((applyXmlFilter (isTag "OMBIND") t)::[XmlTree])
	
xmlToConstraint::HXT.XmlTrees->ABC.Constraint
xmlToConstraint t =
	let 	sortsx = applyXmlFilter (getChildren .> isTag "OMS" .> getValue "name") t
		newsort = Hets.stringToId $ xshow $ [sortsx!!0]
		origsort = Hets.stringToId $ xshow $ [sortsx!!0]
		indiopsx = applyXmlFilter (getChildren .> isTag "OMBVAR" .> getChildren .> isTag "OMATTR") t
		conslist = foldl (\cl cx ->
				let	indices = xshow $ applyXmlFilter (getChildren .> isTag "OMATP" .> getChildren .> isTag "OMSTR" .> getChildren) [cx]
					op = operatorFromXml $ applyXmlFilter (getChildren .> (isTag "OMBIND" +++ isTag "OMS")) [cx]
					il = makeIndexList indices
				in
					cl ++ [(op, il)]
				) ([]::[(OP_SYMB,[Int])]) (indiopsx::[XmlTree])
	in
		ABC.Constraint newsort conslist origsort

-- An IndexList is constructed from a String like 'n1|n2|n3...nk|' 		
makeIndexList::String->[Int]
makeIndexList [] = []
makeIndexList s = let (number, rest) = (takeWhile (\x -> x /= '|') s, dropWhile (\x -> x /= '|') s)
		  in [read number] ++ (makeIndexList (drop 1 rest))


predicationFromXml::XmlTrees->PRED_SYMB
predicationFromXml t =
	let	signature =
			if (applyXmlFilter (isTag "OMATTR") t) /= [] then
				xshow $ applyXmlFilter (
					getChildren .> isTag "OMATP" .>
					getChildren .> isTag "OMSTR" .>
					getChildren ) t
			else
				""
		types = explode "-\\" signature
		prtype = Pred_type (map Hets.stringToId types) Id.nullRange
		symbolXml = if signature == "" then
						applyXmlFilter (isTag "OMS") t
						else
						applyXmlFilter (
							isTag "OMATTR" .>
							getChildren .> isTag "OMS"
							) t
		-- sfrom = xshow $ applyXmlFilter (getValue "cd") symbolXml
		sname = xshow $ applyXmlFilter (getValue "name") symbolXml
	in
	if signature == [] then
		Pred_name $ Hets.stringToId sname
	else
		Qual_pred_name (Hets.stringToId sname) prtype Id.nullRange
		
-- NOTE: need to fix formula generation because new format makes explicit
-- signatures obsolete...
{- there is something to fix before this function can work...						
predicationXNFromXml::FFXInput->AnnXMLN->PRED_SYMB
predicationXNFromXml ffxi anxml = 
	let -}
		{- signature =
			if (applyXmlFilter (isTag "OMATTR") (axXml anxml)) /= [] then
				xshow $ applyXmlFilter (
					getChildren .> isTag "OMATP" .>
					getChildren .> isTag "OMSTR" .>
					getChildren ) (axXml anxml)
			else
				""
		types = explode "-\\" signature
		prtype =
			Pred_type
				(map
					(\t ->
						case findByNameAndOrigin t (axAnn anxml) (xnSortSet ffxi) of
							Nothing -> error "Cannot find argument!"
							(Just txn) -> xnWOaToa txn
					)
					types
				)
				Id.nullRange -}
		{- symbolXml = if signature == "" then
						applyXmlFilter (isTag "OMS") (axXml anxml)
						else
						applyXmlFilter (
							isTag "OMATTR" .>
							getChildren .> isTag "OMS"
							) (axXml anxml) -}
		{- symbolXml = applyXmlFilter (isTag "OMS") (axXml anxml)
		sxname = xshow $ applyXmlFilter (getValue "name") symbolXml
		sxcd = xshow $ applyXmlFilter (getValue "cd") symbolXml
		theonode = case getNodeForTheoryName (xnTheorySet ffxi) sxcd of
			Nothing -> error "No Theory for used predicate!"
			(Just n) -> n
		theoxn = case findByName sxcd (xnTheorySet ffxi) of
			Nothing -> error "No Theory for used predicate!"
			(Just theoxn' ) -> theoxn'
		theopreds = Map.findWithDefault Map.empty (xnName theoxn) (xnPredMap ffxi) 
		predxnid = case findByName sxname (map fst $ Map.toList theopreds) of
			Nothing -> error "No such predicate in Theory!"
			(Just predxnid' ) -> predxnid'
		predXNWON = Map.findWithDefault (error "Predicate not found!") predxnid theopreds
	in
		Qual_pred_name (xnWOaToa predxnid) (cv_PredTypeToPred_type $ predTypeXNWONToPredType predXNWON) Id.nullRange -}

-- String to Quantifiert...
quantFromName::String->QUANTIFIER
quantFromName s
	| (s == caslSymbolQuantUniversalS) = Universal
	| (s == caslSymbolQuantExistentialS) = Existential
	| (s == caslSymbolQuantUnique_existentialS) = Unique_existential
	| otherwise = error (s++": no such quantifier...")

funKindFromName::String->FunKind
funKindFromName "Total" = Total
funKindFromName "Partial" = Total
funKindFromName s = error ("No such function kind... \""++ s ++"\"")


-- first newline needs pulling up because we have a list of lists...
processVarDecl :: Hets.ImportsMap-> Hets.SortsMap-> String -> [VAR_DECL] -> (HXT.XmlTree->HXT.XmlTrees)
processVarDecl imports' sorts' name' vdl = (HXT.etag "OMBVAR" += (xmlNL +++ (processVarDecls imports' sorts' name' vdl)) ) +++ xmlNL where
	processVarDecls :: Hets.ImportsMap-> Hets.SortsMap-> String ->[VAR_DECL] -> (HXT.XmlTree->HXT.XmlTrees)
	processVarDecls _ _ _ [] = HXT.txt ""
	processVarDecls imports'' sorts'' name'' ((Var_decl vl s _):vdl' ) = (foldl (\decls vd -> decls +++
	-- <ombattr><omatp><oms>+</omatp><omv></ombattr>
		( createTypedVar imports'' sorts'' s name'' (show vd) )
			+++ xmlNL)
			(HXT.txt "") vl ) -- end fold
			+++ (processVarDecls imports'' sorts'' name'' vdl' )
	
-- first newline needs pulling up because we have a list of lists...
processVarDeclXN :: TheoryXNSet -> Set.Set XmlNamedWONSORT -> [VAR_DECL] -> (HXT.XmlTree->HXT.XmlTrees)
processVarDeclXN theoryset theorysorts vdl =
	(HXT.etag "OMBVAR" += (xmlNL +++ (processVarDecls theoryset theorysorts vdl)) ) +++ xmlNL
	where
	processVarDecls :: TheoryXNSet -> Set.Set XmlNamedWONSORT -> [VAR_DECL] -> (HXT.XmlTree->HXT.XmlTrees)
	processVarDecls _ _ [] = HXT.txt ""
	processVarDecls theoryset' theorysorts' ((Var_decl vl s _):vdl' ) = (foldl (\decls vd -> decls +++
	-- <ombattr><omatp><oms>+</omatp><omv></ombattr>
		( createTypedVarXN theoryset theorysorts' s (show vd) )
			+++ xmlNL)
			(HXT.txt "") vl ) -- end fold
			+++ (processVarDecls theoryset' theorysorts' vdl' )
			
-- get var decls
getVarDecls::XmlTrees->[(String, String)]
getVarDecls vt = map (\t ->
		(xshow $ applyXmlFilter (getChildren .> isTag "OMATP" .> getChildren .> isTag "OMS" .> withValue "name" (/=typeS) .> getValue "name") [t],
		 xshow $ applyXmlFilter (getChildren .> isTag "OMV" .> getValue "name") [t]) ) ((applyXmlFilter (isTag "OMBVAR" .> getChildren .> isTag "OMATTR") vt)::[XmlTree])

-- reminder : switching to XmlNamed-structures makes use of current theory name obsolete...

createATP::Hets.ImportsMap->Hets.SortsMap->SORT->String->(XmlTree->XmlTrees)
createATP imports' sorts' sort name' =
	etag "OMATP" +=
		((etag "OMS" += ( sattr "cd" caslS +++ sattr "name" typeS ) )
		 +++ createSymbolForSort imports' sorts' sort name'
		 )
		 
createATPXN::TheoryXNSet -> Set.Set XmlNamedWONSORT -> SORT ->(XmlTree->XmlTrees)
createATPXN theoryset theorysorts sort =
	etag "OMATP" +=
		(( etag "OMS" += ( sattr "cd" caslS +++ sattr "name" typeS ) )
		 +++ createSymbolForSortWithSortXNSet theoryset theorysorts sort
		 )
		 
createTypedVar::Hets.ImportsMap->Hets.SortsMap->SORT->String->String->(XmlTree->XmlTrees)
createTypedVar imports' sorts' sort name' varname =
	etag "OMATTR" += ( (createATP imports' sorts' sort name' ) +++ (etag "OMV" += (sattr "name" varname) ) )
	
-- TODO : change to correct types
createTypedVarXN::TheoryXNSet -> Set.Set XmlNamedWONSORT->SORT->String->(XmlTree->XmlTrees)
createTypedVarXN theoryset theorysorts sort varname =
	etag "OMATTR" += ( (createATPXN theoryset theorysorts sort) +++ (etag "OMV" += (sattr "name" varname) ) )
	
-- | create a xml-representation from a term (in context of a theory)
processTerm::
	Hets.ImportsMap-> -- ^ the imports-map
	Hets.SortsMap-> -- ^ the sorts-map
	Hets.PredsMap-> -- ^ the map of predicates
	Hets.OpsMap-> -- ^ the map of operators
	String-> -- ^ the name of the current theory
	(TERM f)-> -- ^ the term to process
	(HXT.XmlTree->HXT.XmlTrees) -- ^ xml-representation of the term
-- Simple_id
processTerm _ _ _ _ _
	(Simple_id id' ) =
		HXT.etag "OMV" +=
			HXT.sattr "name" (show id' ) -- not needed
-- Qual_var
processTerm imports' sorts' _ _ name'
	(Qual_var v s _) =
		( createTypedVar imports' sorts' s name' (show v) ) +++
		xmlNL
-- Application
processTerm imports' sorts' preds' ops' name'
	(Application op termlist _) =
		if null termlist
			then
				(processOperator imports' ops' name' op) +++
				xmlNL
			else
				(etag "OMA" +=
					(xmlNL +++ (HXT.cmt "appl") +++
					( processOperator imports' ops' name' op ) +++
					(foldl (\terms t ->
						terms +++
						(processTerm imports' sorts' preds' ops' name' t)
						) (HXT.cmt "terms") termlist
					)
					) ) +++
					xmlNL
-- Cast
processTerm imports' sorts' preds' ops' name'
	(Cast t s _) =
		processTerm imports' sorts' preds' ops' name'
			(Application
				(Op_name $ Hets.stringToId "PROJ")
				[t, (Simple_id $ Id.mkSimpleId (show s))]
				Id.nullRange
			)
-- Conditional
processTerm imports' sorts' preds' ops' name'
	(Conditional t1 f t2 _) =
		HXT.etag "OMA" +=
			(xmlNL +++
			(HXT.etag "OMS" +=
				(HXT.sattr "cd" caslS +++
				HXT.sattr "name" "IfThenElse"
				)
			) +++
			(processFormula imports' sorts' preds' ops' name' f) +++
			(processTerm imports' sorts' preds' ops' name' t1) +++
			(processTerm imports' sorts' preds' ops' name' t2)
			)
-- Sorted_term is to be ignored in OMDoc (but could be modelled...) (Sample/Simple.casl uses it...)
processTerm imports' sorts' preds' ops' name'
	(Sorted_term t _ _) =
		processTerm imports' sorts' preds' ops' name' t
-- Unsupported Terms...
processTerm _ _ _ _ _ _ = error "Unsupported Term encountered..." 


-- | create a xml-representation from a term (in context of a theory)
processTermXN::
	PFInput->
	(TERM f)-> -- ^ the term to process
	(HXT.XmlTree->HXT.XmlTrees) -- ^ xml-representation of the term
-- Simple_id
processTermXN _
	(Simple_id id' ) =
		HXT.etag "OMV" +=
			HXT.sattr "name" (show id' ) -- not needed
-- Qual_var
processTermXN pfinput
	(Qual_var v s _) =
		( createTypedVarXN (theorySet pfinput) (theorySorts pfinput) s (show v) ) +++
		xmlNL
-- Application
processTermXN pfinput
	(Application op termlist _) =
		if null termlist
			then
				(processOperatorXN pfinput op) +++
				xmlNL
			else
				(etag "OMA" +=
					(xmlNL +++ (HXT.cmt "appl") +++
					( processOperatorXN pfinput op ) +++
					(foldl (\terms t ->
						terms +++
						(processTermXN pfinput t)
						) (HXT.cmt "terms") termlist
					)
					) ) +++
					xmlNL
-- Cast
processTermXN pfinput
	(Cast t s _) =
		processTermXN pfinput
			(Application
				(Op_name $ Hets.stringToId "PROJ")
				[t, (Simple_id $ Id.mkSimpleId (show s))]
				Id.nullRange
			)
-- Conditional
processTermXN pfinput
	(Conditional t1 f t2 _) =
		HXT.etag "OMA" +=
			(xmlNL +++
			(HXT.etag "OMS" +=
				(HXT.sattr "cd" caslS +++
				HXT.sattr "name" "IfThenElse"
				)
			) +++
			(processFormulaXN pfinput f) +++
			(processTermXN pfinput t1) +++
			(processTermXN pfinput t2)
			)
-- Sorted_term is to be ignored in OMDoc (but could be modelled...) (Sample/Simple.casl uses it...)
processTermXN pfinput
	(Sorted_term t _ _) =
		processTermXN pfinput t
-- Unsupported Terms...
processTermXN _ _ = error "Unsupported Term encountered..." 


isTermXml::XmlFilter
isTermXml = isTag "OMV" +++ isTag "OMATTR" +++ isTag "OMA"

isOperatorXml::XmlFilter
isOperatorXml = isTag "OMATTR" +++ isTag "OMS"

isTermOrOpXml::XmlFilter
isTermOrOpXml = isTermXml +++ isTag "OMS" -- never ever use double tags or get double results...

termFromXml::FormulaContext->XmlTrees->(TERM ())
termFromXml fc t = if (applyXmlFilter (isTag "OMV") t) /= [] then
			Simple_id $ Hets.stringToSimpleId $ xshow $ applyXmlFilter (isTag "OMV" .> getValue "name") t
		else
		if (applyXmlFilter (isTag "OMATTR") t) /= [] then
			if applyXmlFilter (isTag "OMATTR" .> getChildren .> isTag "OMATP" .> getChildren .> isTag "OMS" .> withSValue "name" "funtype") t /= []
				then
					Application (operatorFromXml t) [] Id.nullRange
				else
					Qual_var
						(Hets.stringToSimpleId $ xshow $ applyXmlFilter (isTag "OMATTR" .> getChildren .> isTag "OMV" .> getValue "name") t)
						(Hets.stringToId $ xshow $ applyXmlFilter (isTag "OMATTR" .> getChildren .> isTag "OMATP" .> getChildren .> isTag "OMS" .> withValue "name" (/=typeS) .> getValue "name") t)
						Id.nullRange
		else
		if (applyXmlFilter (isTag "OMA") t ) /= [] then
			let operator = operatorFromXml [head $ applyXmlFilter (getChildren .> isOperatorXml) t]
			    terms = map (\n -> termFromXml fc [n]) $
					applyXmlFilter isTermXml $
					drop 1 $ -- drop out operator
					applyXmlFilter (getChildren .> isTermOrOpXml) t
			in
			if (opName operator) == "PROJ" then
				Cast (head terms) (Hets.stringToId $ show (head $ tail terms)) Id.nullRange
			else
			if (opName operator) == "IfThenElse" then
				let	formula = formulaFromXml fc [head ((applyXmlFilter (getChildren .> (isTag "OMA" +++ isTag "OMBIND")) t)::[XmlTree])]
				in 
				Conditional (head terms) formula (head $ tail terms) Id.nullRange 
			else
				Application operator terms Id.nullRange
		else
			error ("Impossible to create term from \"" ++ xshow t++"\"") 

			
cv_Op_typeToOpType::OP_TYPE->OpType
cv_Op_typeToOpType (Op_type fk args res _) = OpType fk args res

cv_OpTypeToOp_type::OpType->OP_TYPE
cv_OpTypeToOp_type (OpType fk args res) = Op_type fk args res Id.nullRange

cv_Pred_typeToPredType::PRED_TYPE->PredType
cv_Pred_typeToPredType (Pred_type args _) = PredType args

cv_PredTypeToPred_type::PredType->PRED_TYPE
cv_PredTypeToPred_type (PredType args) = Pred_type args Id.nullRange


-- | create a xml-representation of an operator (in context of a theory)
processOperator::
	Hets.ImportsMap-> -- ^ the map of imports
	Hets.OpsMap-> -- ^ the map of operators
	String-> -- ^ the name of the current theory
	OP_SYMB-> -- ^ the operator to process
	(XmlTree->XmlTrees) -- ^ the xml-representation of the operator
-- Op_name
processOperator imports' ops' name'
	(Op_name op) =
		HXT.etag "OMS" +=
			(HXT.sattr "cd" 
				(fromMaybe "unknown" $
					Hets.findNodeNameForOperator imports' ops' op name' ) +++
				HXT.sattr "name" (show op)
			)
-- Qual_op_name
processOperator imports' ops' name'
	(Qual_op_name op ot@(Op_type fk args res _) _) =
		HXT.etag "OMATTR" +=
			(xmlNL +++
			HXT.etag "OMATP" += -- create attribution for this operator (sign)
				(xmlNL +++
				HXT.etag "OMS" += -- type of operator
					(HXT.sattr "cd" "casl" +++
					HXT.sattr "name" "funtype"
					) +++
				xmlNL +++
				(HXT.etag "OMSTR" +=
					(HXT.txt (show fk)) -- 'Partial' or 'Total'
				) +++
				xmlNL +++
				HXT.etag "OMS" += -- signature of operator
					(HXT.sattr "cd" "casl" +++
					HXT.sattr "name" "type"
					) +++
				xmlNL +++
				(HXT.etag "OMSTR" += -- create a string t1-\\t2-\\...-\\tn
					(HXT.txt ( (foldl
						(\t s -> t ++ (show s) ++ "-\\")
						-- the function could be easier but we need different
						-- behaviour for functions without parameters...
						(if (length args > 0) then
								(show (head args)) ++ "-\\"
							else
								"" )
						(if (length args) > 0 then tail args else [])
						) ++ (show res) )
					)
				) +++
				xmlNL
				) +++
				xmlNL +++
				HXT.etag "OMS" += -- finally : the name of the operator
					( HXT.sattr "cd"
						( fromMaybe "unknown" $
							Hets.findNodeNameForOperatorWithSorts
								imports'
								ops'
								(op, cv_Op_typeToOpType ot) name'
						) +++
						HXT.sattr "name" (show op)
					)
			)
		

-- | create a xml-representation of an operator (in context of a theory)
processOperatorXN::
	PFInput->
	OP_SYMB-> -- ^ the operator to process
	(XmlTree->XmlTrees) -- ^ the xml-representation of the operator
-- Op_name
processOperatorXN pfinput
	(Op_name op) =
		let
			(xnopid, _) =
				case find
						(\(xnid, _) -> (xnWOaToa xnid) == op)
						(theoryOps pfinput)	of
							Nothing -> error "Operator is unknown!"
							(Just x' ) -> x'
		in
			HXT.etag "OMS" +=
				(HXT.sattr "cd" 
					(fromMaybe "unknown" $
						getTheoryXmlName (theorySet pfinput) (xnWOaToO xnopid)) +++
					HXT.sattr "name" (xnName xnopid)
				)
-- Qual_op_name
processOperatorXN pfinput
	(Qual_op_name op ot _) =
		let
			(xnopid, _) =
				case find
					(\(xnid, xnopt) ->
						(xnWOaToa xnid) == op
						&& (cv_OpTypeToOp_type $ opTypeXNWONToOpType xnopt) == ot
					)
					(theoryOps pfinput) of
						Nothing -> error "Operator is unknown!"
						(Just x' ) -> x' 
		in
			HXT.etag "OMS" +=
				( HXT.sattr "cd"
					( fromMaybe "unknown" $
						getTheoryXmlName (theorySet pfinput) (xnWOaToO xnopid)
					) +++
					HXT.sattr "name" (xnName xnopid)
				)

			
trim::(a->Bool)->[a]->[a]
trim test list = dropWhile test (reverse (dropWhile test (reverse list)))

trimString::String->String
trimString = trim (Char.isSpace)
			
implode::[a]->[[a]]->[a]
implode _ [] = []
implode _ [last' ] = last'
implode with (item:rest) = item ++ with ++ (implode with rest)
			
-- explode byWhat list
-- TODO : this looks very slow...
explode::Eq a=>[a]->[a]->[[a]]
explode by list =
	(\(p,q) -> p++[q]) $ foldl (\(exploded, current) newchar ->
		let newcurrent = current ++ [newchar]
		in
		if isSuffixOf by newcurrent then
			(exploded ++ [ take ((length newcurrent)-length(by)) newcurrent ], [])
		else
			(exploded, newcurrent)
			) ([],[]) list


-- this function takes care of fetching the function-type information from an 
-- OMATTR-Tree (defaulting to Total but raising exception on 'explicit-wrong' type
-- usually the 'skipping-part' will not have to skip over many items (1-2) 
getFunKind::XmlTrees->FunKind
getFunKind t =
	if (applyXmlFilter (isTag "OMATTR") t) /= [] then
		(\ (a,_,_) -> a ) $ foldl (\(fk, found, skip) tc ->
			if skip then (fk, found, skip)
			else
				if not found then
					if (applyXmlFilter (isTag "OMS" .> withSValue "name" "funtype") [tc]) /= [] then
						(fk, True, skip)
					else
						(fk, found, skip)
				else
					if (applyXmlFilter (isTag "OMSTR") [tc]) /= [] then
						(funKindFromName $ xshow $ applyXmlFilter (getChildren) [tc], True, True)
					else
						(fk, found, skip)
					) (Total, False, False) $ applyXmlFilter (getChildren .> isTag "OMATP" .> getChildren) t
	else
		Total

-- fetches signature from XML (see getFunKind)		
getSignature::XmlTrees->([SORT], SORT)
getSignature t =
	if (applyXmlFilter (isTag "OMATTR") t) /= [] then
		(\ (a,_,_) -> a ) $ foldl (\(sig, found, skip) tc ->
			if skip then (sig, found, skip)
			else
				if not found then
					if (applyXmlFilter (isTag "OMS" .> withSValue "name" "type") [tc]) /= [] then
						(sig, True, skip)
					else
						(sig, found, skip)
				else
					if (applyXmlFilter (isTag "OMSTR") [tc]) /= [] then
						let args = map Hets.stringToId $ explode "-\\" $ xshow $ applyXmlFilter (getChildren) [tc]
						in
						((init args, last args), True, True)
					else
						(sig, found, skip)
					) (([],Hets.stringToId ""), False, False) $ applyXmlFilter (getChildren .> isTag "OMATP" .> getChildren) t
	else
		([], Hets.stringToId "")


operatorFromXml::XmlTrees->OP_SYMB
operatorFromXml t =
	let	funkind = getFunKind t
		(sig,res) = getSignature t
		optype = Op_type funkind sig res Id.nullRange
		symbolXml = if (res == (Hets.stringToId "")) then
						applyXmlFilter (isTag "OMS") t
						else
						applyXmlFilter (
							isTag "OMATTR" .>
							getChildren .> isTag "OMS"
							) t
		-- sfrom = xshow $ applyXmlFilter (getValue "cd") symbolXml
		sname = xshow $ applyXmlFilter (getValue "name") symbolXml
	in
	if (res == (Hets.stringToId "")) then
		Op_name $ Hets.stringToId sname
	else
		Qual_op_name (Hets.stringToId sname) optype Id.nullRange
		
getSorts::XmlTrees->[String]
getSorts st = map (\t -> xshow $ applyXmlFilter (getValue "name") [t]) ((applyXmlFilter (getChildren .> isTag "OMATP" .> getChildren .> isTag "OMS" .> withValue "name" (/=typeS)) st)::[XmlTree])

opName::OP_SYMB->String
opName (Op_name op) = (show op)
opName (Qual_op_name op _ _) = (show op)

idToString::Id.Id->String
idToString (Id.Id toks ids _) =
		"[" ++
		(implode "," (map (\(Id.Token s _) -> s) toks)) ++
		(implode "," (map idToString ids)) ++
		"]"
		
-- this encapsulates a node_name in an id
nodeNameToId::NODE_NAME->Id.Id
nodeNameToId (s,e,n) = Id.mkId [s,(Hets.stringToSimpleId e),(Hets.stringToSimpleId (show n))]

-- this reads back an encapsulated node_name
idToNodeName::Id.Id->NODE_NAME
idToNodeName (Id.Id toks _ _) = (toks!!0, show (toks!!1), read (show (toks!!2)))
	
		
instance Read Id.Id where
	readsPrec _ s =
		let
			(_,r) = (\s' -> (takeWhile Char.isSpace s' , dropWhile Char.isSpace s' )) s
		in
			case r of
				('[':t) ->
					let
						tokens = takeWhile (not . (flip elem [']','['])) t
						token = map (\str -> Id.Token (trimString str) Id.nullRange) (explode "," tokens)
						rest = drop (length tokens) t
						(ids, newrest) = until
							(\(_,sr' ) -> case sr' of (h:_) -> h==']'; _ -> True )
							(\(ids' , sr' ) ->
								case (readsPrec 0 sr' )::([(Id.Id, String)]) of
									[] -> error ("Error parsing Id from \" " ++ sr' ++ "\"") 
									((id' , nr):_) -> (ids' ++ [id' ], nr )
							)
							([], rest) 
					in
						case newrest of
						(']':_) -> [(Id.Id token ids Id.nullRange, drop 1 newrest)]
						_ -> []
				_ -> []
		
idToXml::Id.Id->(HXT.XmlTree->HXT.XmlTrees)
idToXml id' = HXT.cdata (idToString id' )

idFromXml::HXT.XmlTrees->Id.Id
idFromXml = read . xshow . applyXmlFilter getChildren


		
createPresentationForId::Id.Id->String->HXT.XmlFilter
createPresentationForId theId givenName =
	HXT.etag "presentation" += (
			(HXT.sattr "for" givenName)
		+++ xmlNL
		+++	(HXT.etag "use" += (
					(HXT.sattr "format" "Hets")
				+++	(HXT.txt (idToString theId)) 
				))
		+++	xmlNL
		)
		
createIdFromPresentation::HXT.XmlTree->Id.Id
createIdFromPresentation t =
	let
		idString = xshow $ applyXmlFilter (getChildren .> isTag "use" .>
			withSValue "format" "Hets" .> getChildren) [t]
	in
		read idString
		
type XmlName = String
-- this type is used to store already used names
type XmlNameList = [XmlName]

data XmlNamed a = XmlNamed { xnItem::a, xnName::XmlName }

instance (Eq a)=>Eq (XmlNamed a) where
	x1 == x2 = (xnItem x1) == (xnItem x2)

instance (Ord a)=>Ord (XmlNamed a) where
	compare x1 x2 = compare (xnItem x1) (xnItem x2)

instance (Show a)=>Show (XmlNamed a) where
	show x = (show $ xnItem x) ++ " xml:(" ++ (xnName x) ++ ")"

-- | Container-Class	
class Container a b | a -> b where
	getItems::a->[b]
	fromItems::[b]->a
	
-- | Container-Conversion
con_convert::(Container q i, Container r i)=>q->r
con_convert c = fromItems (getItems c)

-- | Container-Mapping
con_map::(Container q i, Container r j)=>(i->j)->q->r
con_map f = fromItems . (map f) . getItems

-- Lists are containers
instance Container [a] a where
	getItems = id
	fromItems = id
	
-- Sets are containers
instance (Ord a)=>Container (Set.Set a) a where
	getItems = Set.toList
	fromItems = Set.fromList
	
-- Maps are containers
instance (Ord a)=>Container (Map.Map a b) (a,b) where
	getItems = Map.toList
	fromItems = Map.fromList
	
-- Relations are containers
instance (Ord a)=>Container (Rel.Rel a) (a,a) where
	getItems = Rel.toList
	fromItems = Rel.fromList	
	
-- | remove characters from a String to use it in xml
-- follows the xml Name-production-rule (without combining-char and extender)
adjustStringForXmlName::String->XmlName
adjustStringForXmlName [] = "Empty"
adjustStringForXmlName s@(firstChar:_) =
	preventEmpty $
	if (Char.isDigit firstChar)
		then
			adjustStringForXmlName ("N"++s)
		else
			filter
				(\c ->
					-- xml-names may contain letters, digits and
					-- the symbols shown below
					(isAscii c)
					&&	(
						(isAlphaNum c)
						||	(elem c [':','_','.','-'])
						)
				)
				-- remove everything until a letter or ':' or '_' is found
				(dropWhile
					(\c ->
						not (
							(isAlpha c)
							||	(elem c [':', '_'])
							)
					)
					(replaceSpecial s)
				)
	where
		replaceSpecial::String->String
		replaceSpecial [] = []
		replaceSpecial ('\194':r) = replaceSpecial r -- Unicode (Â in ISO-8859-15...)
		replaceSpecial (c:r) =
			case c of
				' ' -> "_"
				'*' -> "Ast"
				'<' -> "Lower"
				'>' -> "Greater"
				';' -> "SemiColon"
				'/' -> "Division"
				'+' -> "Plus"
				'-' -> "Minus"
				'%' -> "Percent"
				'(' -> "BrackOpen"
				')' -> "BrackClose"
				'{' -> "BraceOpen"
				'}' -> "BraceClose"
				'[' -> "SBrackOpen"
				']' -> "SBrackClose"
				'=' -> "Equals"
				',' -> "Comma"
				'#' -> "Hash"
				'\'' -> "SQuote"
				'"' -> "Quote"
				'~' -> "Tilde"
				'`' -> "AccGrav"
				'\\' -> "Backslash"
				'!' -> "Excla"
				'?' -> "Quest"
				'@' -> "At"
				'$' -> "Dollar"
				'&' -> "Amp"
				'^' -> "Circ"
				'\167' -> "Para"
				'\176' -> "Degree"
				_ -> [c]
			++ replaceSpecial r
		preventEmpty::String->String
		preventEmpty [] = "Empty"
		preventEmpty q = q

-- | create unique xml-names for a list of items with a list of previous names
-- and a naming function and return resulting list and list of used names
createXmlNames::(a->String)->XmlNameList->[a]->([XmlNamed a], XmlNameList)
createXmlNames = createXmlNamesCon
	
-- | create unique names for items in a container with a list of previous names
-- and a naming function and return a container of named elements and a list
-- of used names
createXmlNamesCon::(Container q a, Container r (XmlNamed a))=>(a->String)->XmlNameList->q->(r, XmlNameList)
createXmlNamesCon nameForItem xmlnames container =
	let
		items = getItems container
		(newitems, newnames) = foldl (\(items' , xmlnames' ) item ->
			let
				initialname = adjustStringForXmlName (nameForItem item)
				finalitemname = createUniqueName xmlnames' initialname
			in
				(items' ++ [XmlNamed item finalitemname], finalitemname:xmlnames' )
				) ([], xmlnames) items
	in
		(fromItems newitems, newnames)

-- | create unique names for a list of items providing a function to check if
-- two elements are equal
uniqueXmlNames::XmlNameList->(a->a->Bool)->(a->String)->[a]->([XmlNamed a], XmlNameList)
uniqueXmlNames xmlnames isequal tostring =
	foldl (\(xmlnamed, xmlnames' ) listitem ->
	let
		initialname = adjustStringForXmlName (tostring listitem)
		itemname = createUniqueName xmlnames' initialname 
	in
		case find ((isequal listitem) . xnItem) xmlnamed of
			Nothing ->  ( (XmlNamed listitem itemname):xmlnamed, itemname:xmlnames' )
			(Just previous) -> ((XmlNamed listitem (xnName previous)):xmlnamed , xmlnames' )
	) ([],xmlnames)

-- | unique xml names for container	
uniqueXmlNamesContainer::(Container c i, Container d (XmlNamed i))=>
	XmlNameList->
	(a->String)-> -- ^ how to find an initial name for a converted item
	c->
	(i->i->Bool)->
	(i->a)-> -- ^ specify a conversion of items (or 'id')
	(d, XmlNameList)
uniqueXmlNamesContainer
	xmlnames
	tostring
	container
	isequal
	conversion =
		let
			items = getItems container
			(newitems, newxmlnames) =
				foldl(\(newitems' , newxmlnames' ) listitem ->
					let
						converted = conversion listitem
						initialname = adjustStringForXmlName (tostring converted)
						itemname = createUniqueName newxmlnames' initialname
					in
						case find ((isequal listitem) . xnItem) newitems' of
							Nothing -> ( (XmlNamed listitem itemname):newitems' , itemname:newxmlnames' )
							(Just previous) -> ((XmlNamed listitem (xnName previous)):newitems' , newxmlnames' )
					) ([], xmlnames) items
		in
			(fromItems newitems, newxmlnames)
	
-- | use this function to process containers that are stored in other containers
--  - think map key->container - and return container with containers of processed 
-- items. the trick is that the key association is the same as long as the 
-- processing function does not alter the key (but it may do so)
-- the processing function needs to take an initial status and the final status 
-- will be returned
processSubContents::(Ord k, Container a (k, p), Container p q, Container t r, Container b (k, t))=>
	(s->[(k, q)]->([(k, r)], s))->s->a->(b, s)
processSubContents
	subprocess
	startvalue
	container =
	let
		allitems = getItems container
		tagged = concatMap (\(k,c) -> map (\i -> (k,i)) (getItems c)) allitems
		(processeditems, finalstatus) = subprocess startvalue tagged
		sorted = foldl (\sorted' (k,i) ->
			insertAtKey (k,i) sorted'
			) [] processeditems
		kconpairs = map (\(k,l) -> (k,fromItems l)) sorted
	in
		(fromItems kconpairs, finalstatus)
	where
	insertAtKey::(Eq k)=>(k,v)->[(k,[v])]->[(k,[v])]
	insertAtKey (k,v) [] = [(k,[v])]
	insertAtKey (k,v) ((lk,l):r) =
		if k == lk then (lk,v:l):r else (lk,l):(insertAtKey (k,v) r)

-- strip-function for using processSubContents		
pSCStrip::(a->b)->(z,a)->b
pSCStrip f (_,a) = f a

-- creates a unique name from an initial name and a list of used names
-- the returned string will be the initial name or the initial name with a
-- number appended
createUniqueName::XmlNameList->String->String
createUniqueName
	xmlnames initialname =
		initialname ++
			(nzshow
				(until
					(\n -> not $ elem (initialname ++ (nzshow n)) xmlnames)
					(+1)
					0
				)
			)
	where
	nzshow::Int->String
	nzshow 0 = ""
	nzshow i = show i

-- | unique xml names for container	
uniqueXmlNamesContainerExt::(Container c i, Container d j)=>
	XmlNameList->
	(a->String)-> -- ^ how to find an initial name for a converted item
	c->
	(a->a->Bool)->
	(i->a)-> -- ^ specify a conversion of items (or 'id')
	(i->XmlName->j)->
	(d, XmlNameList)
uniqueXmlNamesContainerExt
	xmlnames
	tostring
	container
	isequal
	extract
	synthesize =
		let
			items = getItems container
			(newitems, newxmlnames) =
				foldl(\(newitems' , newxmlnames' ) listitem ->
					let
						extracted = extract listitem
						initialname = adjustStringForXmlName (tostring extracted)
						itemname = createUniqueName newxmlnames' initialname
					in
						case find ((isequal extracted) . extract . fst) newitems' of
							Nothing -> ( (listitem, itemname):newitems' , itemname:newxmlnames' )
							(Just (_, pname)) -> ( (listitem, pname):newitems' , newxmlnames' )
					) ([], xmlnames) items
		in
			(fromItems (map (uncurry synthesize) newitems), newxmlnames)
			
uniqueXmlNamesContainerWONExt::(Container c i, Container d j, Eq a)=>
	XmlNameList->
	(a->String)-> -- ^ how to find an initial name for a converted item
	c->
	(i->(Hets.WithOriginNode a))-> -- ^ specify a conversion of items (or 'id')
	(i->XmlName->j)->
	(d, XmlNameList)
uniqueXmlNamesContainerWONExt xmlnames tostring container extract synthesize =
	uniqueXmlNamesContainerExt
		xmlnames
		(tostring . Hets.woItem)
		container
		(\p q -> p == q) -- sameOrigin and equalItem
		extract
		synthesize
	
attributeCon::(Container c a, Container d b, Container q r)=>
	(a->b->Bool)->
	a->
	(a->b->r)->
	c->
	d->
	q
attributeCon
	attribmatch
	defaultAttribute
	attribute
	source
	target =
	let
		attributeitems = getItems source
		targetitems = getItems target
		newitems = map (\i ->
			attribute
				(case find ((flip attribmatch) i) attributeitems of
					Nothing -> defaultAttribute
					(Just attribItem) -> attribItem)
				i) targetitems
	in
		fromItems newitems
		
attributeWithXmlNamesCon::(Container c (XmlNamed a), Container d b, Container q r)=>
	(a->b->Bool)->
	(XmlName->b->r)
	->c
	->d
	->q
attributeWithXmlNamesCon
	matched
	attribute =
	attributeCon
		(\a b -> matched (xnItem a) b)
		(error "Unknown Element!")
		(\a b -> attribute (xnName a) b)
	
uniqueXmlNamesContainerWON::(Eq i, Container c (Hets.WithOriginNode i), Container d (XmlNamed (Hets.WithOriginNode i)))=>
	XmlNameList->
	(a->String)->
	c->
	(i->a)->
	(d, XmlNameList)
uniqueXmlNamesContainerWON
	xmlnames
	tostring
	container
	extract =
		uniqueXmlNamesContainer
			xmlnames
			tostring
			container
			(\a b -> a == b) -- sameOrigin and equalItem
			(extract . Hets.woItem)

