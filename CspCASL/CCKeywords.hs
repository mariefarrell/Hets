{- |
Module      :  $Header$
Copyright   :  (c)  Daniel Pratsch and Uni Bremen 2002-2003
Licence     :  similar to LGPL, see HetCATS/LICENCE.txt or LIZENZ.txt

Maintainer  :  hets@tzi.de
Stability   :  provisional
Portability :  portable
  

CSP-CASL keywords defined as strings to provide consistent keyword
usage.

-}

module CspCASL.CCKeywords where

import Common.Keywords(dataS)

ccspecS, channelS, processS, letS, skipS, stopS, intChoiceS, synParaS
  , interParaS, hidingS, prefixS, sendS, receiveS, chanRenS :: String

oRBracketS, cRBracketS, oSBracketS, cSBracketS, multiPreS, extChoiceS
  , oRenamingS, cRenamingS, oAlPaS, cAlPaS, oGenPaS, mGenPaS, cGenPaS :: String

-- AMGQ: Looks like putting an "S" on the end is a convention
-- throughout Hets, certainly it's used in Common/Keywords.hs

ccspecS    = "ccspec"
channelS   = "channel"
processS   = "process"
letS       = "let"
skipS      = "skip"
stopS      = "stop"

-- "[" is a separator and cannot be excluded from identifiers
oRBracketS = "("
cRBracketS = ")"
oSBracketS = "["
cSBracketS = "]"
multiPreS  = "[]" 
extChoiceS = "[]"
oAlPaS     = "[|"
cAlPaS     = "|]"
oGenPaS    = "["
mGenPaS    = "||"
cGenPaS    = "]"
oRenamingS = "[["
cRenamingS = "]]"

synParaS   = "||"
intChoiceS = "|~|"
interParaS = "|||"
hidingS    = "\\"
prefixS    = "->"
sendS      = "!"
receiveS   = "?"
chanRenS   = "<-"

csp_casl_keywords :: [String]
csp_casl_keywords = 
 [ccspecS, dataS, channelS, processS, letS, skipS, stopS, intChoiceS, synParaS
	   , interParaS, hidingS, prefixS, sendS, receiveS, chanRenS]
