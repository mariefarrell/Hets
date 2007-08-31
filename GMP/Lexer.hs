module GMP.Lexer where

import Text.ParserCombinators.Parsec
import Text.ParserCombinators.Parsec.Language
import qualified Text.ParserCombinators.Parsec.Token as T

-------------------------------------------------------------------------------
-- The lexer
-------------------------------------------------------------------------------
lexer :: T.TokenParser st
lexer = T.makeTokenParser gmpDef

parens :: CharParser st a -> CharParser st a
parens          = T.parens lexer

whiteSpace :: CharParser st ()
whiteSpace = T.whiteSpace lexer

natural :: CharParser st Integer
natural = T.natural lexer

gmpDef :: LanguageDef st
gmpDef
    = haskellStyle
    { identStart        = letter
    , identLetter       = alphaNum <|> oneOf "_'" -- ???
    , opStart           = opLetter gmpDef
    , opLetter          = oneOf "\\-<>/~[]"
    , reservedOpNames   = ["~","->","<-","<->","/\\","\\/","[]","<>"]
    }
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
