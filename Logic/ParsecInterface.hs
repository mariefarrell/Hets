{-| 
   
Module      :  $Header$
Copyright   :  (c) Till Mossakowski, Uni Bremen 2002-2004
Licence     :  similar to LGPL, see HetCATS/LICENCE.txt or LIZENZ.txt

Maintainer  :  hets@tzi.de
Stability   :  provisional
Portability :  non-portable (via Logic)

   Interface for Parsec parsers.
   Generates a ParseFun as needed by Logic.hs
-}

module Logic.ParsecInterface
where

import Logic.Logic
import Common.Lib.Parsec
-- import Common.Lib.Parsec.Error

-- for a Parsec parser and an initial state, obtain a ParseFun as needed in Logic.hs

toParseFun :: GenParser Char st a -> st -> ParseFun a  
toParseFun p init pos s = 
   case runParser (do setPosition pos
                      x <- p 
                      s1 <- getInput
                      pos1 <- getPosition
                      return (x,s1,pos1)) 
           init (sourceName pos) s of
     Left err -> error (show err)
     Right x -> x
