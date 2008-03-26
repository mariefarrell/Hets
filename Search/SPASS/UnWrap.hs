module Search.SPASS.UnWrap where


import Data.List (nubBy,partition)
import Search.SPASS.DFGParser hiding (formula)
import Search.SPASS.Sign
import Text.ParserCombinators.Parsec
import Search.Common.Normalization --(normalize,Formula,Const,TrueAtom)
import Search.SPASS.FormulaWrapper (wrapTerm,SpassConst)
import Search.DB.Connection (multiInsertProfiles,insertStatistics,ProfileTuple)

 
type LibraryName = String
type TheoryName = String
type DFGSkeleton = Formula (Constant SpassConst) Int
type LineNr = Int
data Role = Axiom | Theorem deriving (Eq, Ord, Show)
type DFGFormula = (SPTerm, LineNr, Role)
type DFGParameter = String
type Strength = String

data Profile f s p =
    Profile 
    { libName ::LibraryName,
      theoryName :: TheoryName,
      lineNr :: Int,
      formula :: f,
      skeleton :: s,
      parameter :: [p],
      role :: Role,
      strength :: Strength
    } deriving (Eq, Ord, Show)

--type Profile' p = (Skel, [p], LineNr, SenType)
-- (lib,theory,lineNr,spterm,skel,pars,role,strength)
type DFGProfile = Profile SPTerm DFGSkeleton DFGParameter

readDFGFormulae :: SourceName -> IO [DFGFormula]
readDFGFormulae file = (readProblem file) >>= (return . getDFGFormulae)

readProblem :: SourceName -> IO SPProblem
readProblem filePath =
    do result <- parseFromFile parseSPASS filePath
       case result 
         of Left err  -> error $ show err
	    Right spproblem  -> return spproblem

dfgNormalize (lib,theory) (spterm, lineNr, role) = 
    Profile lib theory lineNr spterm skel pars role strength
         where (skel,pars,strength) = normalize $ wrapTerm spterm


getDFGFormulae :: SPProblem -> [DFGFormula]
getDFGFormulae spproblem = concatMap unWrapFormulaList flsts
    where (SPProblem _ _ (SPLogicalPart _ _ flsts) _) = spproblem 

unWrapFormulaList :: SPFormulaList -> [DFGFormula]
unWrapFormulaList flst = map (toDFGFormula role) (formulae flst)
    where role = case originType flst
                 of SPOriginAxioms -> Axiom
                    SPOriginConjectures -> Theorem



toDFGFormula :: Role -> Named SPTerm -> (SPTerm, Int, Role)
toDFGFormula role sen = (spterm, lineNr, role)
    where spterm = sentence sen
          lineNr = read $ senName sen


{-
 for Intersection
-}



{-
 for Indexing
-}

{-

in DB.Connection it should be:
multiInsertProfiles :: Profile ... -> IO ()
-}