{- |
Module      :  $Header$
Description :  Generic Prover GUI.
Copyright   :  (c) Klaus L�ttich, Rainer Grabbe, Uni Bremen 2006
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  rainer25@tzi.de
Stability   :  provisional
Portability :  needs POSIX

Generic GUI for automatic theorem provers. Based upon former SPASS Prover GUI.

-}

{- ToDo:
      - window opens too small on linux; why? ... maybe fixed
      --> failure still there, opens sometimes too small (using KDE),
          but not twice in a row

      - keep focus of listboxes if updated (also relevant for
        in GUI.ProofManagement)

-}

module GUI.GenericATP where

import Logic.Prover

import qualified Common.AS_Annotation as AS_Anno
import qualified Common.Lib.Map as Map

import Data.List
import Data.Maybe
import Data.IORef
import qualified Control.Exception as Exception
import qualified Control.Concurrent as Concurrent

import GHC.Read
import System
import System.IO.Error

import HTk
import SpinButton
import Messages
import TextDisplay
import Separator
import XSelection
import Space

import GUI.HTkUtils
import GUI.GenericATPState

-- debugging
import Debug.Trace


-- * Data Structures and assorted utility functions

data ThreadState = TSt { batchId :: Maybe Concurrent.ThreadId
                       , batchStopped :: Bool
                       }

initialThreadState :: ThreadState
initialThreadState = TSt { batchId = Nothing
                         , batchStopped = False}

{- |
  Utility function to set the time limit of a Config.
  For values <= 0 a default value is used.
-}
setTimeLimit :: Int -> GenericConfig proof_tree -> GenericConfig proof_tree
setTimeLimit n c = if n > 0 then c{timeLimit = Just n}
                   else c{timeLimit = Nothing}

{- |
  Utility function to set the extra options of a Config.
-}
setExtraOpts :: [String] -> GenericConfig proof_tree -> GenericConfig proof_tree
setExtraOpts opts c = c{extraOpts = opts}

{- |
  Checks whether an ATPRetval indicates that the time limit was
  exceeded.
-}
isTimeLimitExceeded :: ATPRetval -> Bool
isTimeLimitExceeded ATPTLimitExceeded = True
isTimeLimitExceeded _ = False


{- |
  Adjusts the configuration associated to a goal by applying the supplied
  function or inserts a new emptyConfig with the function applied if there's
  no configuration associated yet.

  Uses Map.member, Map.adjust, and Map.insert for the corresponding tasks
  internally.
-}
adjustOrSetConfig :: (Ord proof_tree) =>
                     (GenericConfig proof_tree -> GenericConfig proof_tree)
                     -- ^ function to be applied against the current
                     -- configuration or a new emptyConfig
                  -> String -- ^ name of the prover
                  -> ATPIdentifier -- ^ name of the goal
                  -> proof_tree -- ^ initial empty proof_tree
                  -> GenericConfigsMap proof_tree -- ^ current GenericConfigsMap
                  -> GenericConfigsMap proof_tree
                  -- ^ resulting GenericConfigsMap with the changes applied
adjustOrSetConfig f prName k pt m = if (Map.member k m)
                                    then Map.adjust f k m
                                    else Map.insert k
                                               (f $ emptyConfig prName k pt) m

{- |
  Performs a lookup on the ConfigsMap. Returns the config for the goal or an
  empty config if none is set yet.
-}
getConfig :: (Ord proof_tree) =>
             String -- ^ name of the prover
          -> ATPIdentifier -- ^ name of the goal
          -> proof_tree -- ^ initial empty proof_tree
          -> GenericConfigsMap proof_tree
          -> GenericConfig proof_tree
getConfig prName genid pt m = maybe (emptyConfig prName genid pt)
                                id lookupId
  where
    lookupId = Map.lookup genid m

filterOpenGoals :: GenericConfigsMap proof_tree -> GenericConfigsMap proof_tree
filterOpenGoals = Map.filter isOpenGoal
    where isOpenGoal cf = case (goalStatus $ proof_status cf) of
                              Open -> True
                              _    -> False

-- ** Constants

{- |
  Default time limit for the GUI mode prover in seconds.
-}
guiDefaultTimeLimit :: Int
guiDefaultTimeLimit = 10


-- ** Defining the view

{- |
  Colors used by the GUI to indicate the status of a goal.
-}
data ProofStatusColour
  -- | Proved
  = Green
  -- | Proved, but theory is inconsitent
  | Brown
  -- | Disproved
  | Red
  -- | Open
  | Black
  -- | Running
  | Blue
   deriving (Bounded,Enum,Show)

{- |
  Generates a ('ProofStatusColour', 'String') tuple representing a Proved proof
  status.
-}
statusProved :: (ProofStatusColour, String)
statusProved = (Green, "Proved")

statusProvedButInconsistent :: (ProofStatusColour, String)
statusProvedButInconsistent = (Brown, "Proved (Theory inconsistent!)")

{- |
  Generates a ('ProofStatusColour', 'String') tuple representing a Disproved
  proof status.
-}
statusDisproved :: (ProofStatusColour, String)
statusDisproved = (Red, "Disproved")

{- |
  Generates a ('ProofStatusColour', 'String') tuple representing an Open proof
  status.
-}
statusOpen :: (ProofStatusColour, String)
statusOpen = (Black, "Open")

{- |
  Generates a ('ProofStatusColour', 'String') tuple representing an Open proof
  status in case the time limit has been exceeded.
-}
statusOpenTExceeded :: (ProofStatusColour, String)
statusOpenTExceeded = (Black, "Open (Time is up!)")

{- |
  Generates a ('ProofStatusColour', 'String') tuple representing a Running proof
  status.
-}
statusRunning :: (ProofStatusColour, String)
statusRunning = (Blue, "Running")

{- |
  Converts a 'Proof_status' into a ('ProofStatusColour', 'String') tuple to be
  displayed by the GUI.
-}
toGuiStatus :: GenericConfig proof_tree -- ^ current prover configuration
            -> (Proof_status a) -- ^ status to convert
            -> (ProofStatusColour, String)
toGuiStatus cf st = case goalStatus st of
  Proved mc -> maybe (statusProved)
                     ( \ c -> if c
                              then statusProved
                              else statusProvedButInconsistent)
                     mc
  Disproved -> statusDisproved
  _         -> if timeLimitExceeded cf
               then statusOpenTExceeded
               else statusOpen

{-| stores widgets of an options frame and the frame itself -}
data OpFrame = OpFrame { of_Frame :: Frame
                       , of_timeSpinner :: SpinButton
                       , of_timeEntry :: Entry Int
                       , of_optionsEntry :: Entry String
                       }

{- |
  Generates a list of 'GUI.HTkUtils.LBGoalView' representations of all goals
  from a 'GenericATPState.GenericState'.
-}
goalsView :: GenericState sign sentence proof_tree pst -- ^ current global prover state
          -> [LBGoalView] -- ^ resulting ['LBGoalView'] list
goalsView s = map (\ g ->
                       let cfg = Map.lookup g (configsMap s)
                           statind = maybe LBIndicatorOpen
                                       (indicatorFromProof_status . proof_status)
                                       cfg
                        in
                          LBGoalView {statIndicator = statind,
                                      goalDescription = g})
                   (map AS_Anno.senName (goalsList s))

-- * GUI Implementation

-- ** Utility Functions

{- |
  Retrieves the value of the time limit 'Entry'. Ignores invalid input.
-}
getValueSafe :: Int -- ^ default time limt
             -> Entry Int -- ^ time limit 'Entry'
             -> IO Int -- ^ user-requested time limit or default in case of a parse error
getValueSafe defaultTimeLimit timeEntry =
    Exception.catchJust Exception.userErrors ((getValue timeEntry) :: IO Int)
                  (\ s -> trace ("Warning: Error "++show s++" was ignored")
                                (return defaultTimeLimit))

{- |
  Text displayed by the batch mode window.
-}
batchInfoText :: Int -- ^ batch time limt
              -> Int -- ^ total number of goals
              -> Int -- ^ number of that have been processed
              -> String
batchInfoText tl gTotal gDone =
  let totalSecs = (gTotal - gDone) * tl
      (remMins,secs) = divMod totalSecs 60
      (hours,mins) = divMod remMins 60
  in
  "Batch mode runnig\n"++
  show gDone ++ "/" ++ show gTotal ++ " goals processed.\n" ++
  "At most "++show hours++"h "++show mins++"m "++show secs++"s remaining."

-- ** Callbacks

{- |
  Called every time a goal has been processed in the batch mode gui.
-}
goalProcessed :: (Ord proof_tree) =>
                 IORef (GenericState sign sentence proof_tree pst)
               -- ^ IORef pointing to the backing State data structure
              -> Int -- ^ batch time limit
              -- -> String -- ^ extra options
              -> Int -- ^ total number of goals
              -> Label -- ^ info label
              -> String -- ^ name of the prover
              -> Int -- ^ number of goals processed so far
              -> AS_Anno.Named sentence -- ^ goal that has just been processed
              -> (ATPRetval, GenericConfig proof_tree)
              -> IO Bool
goalProcessed stateRef tLimit numGoals label prName
              processedGoalsSoFar nGoal (retval, res_cfg) = do
  s <- readIORef stateRef
  let s' = s{
      configsMap = adjustOrSetConfig
                      (\ c -> c{timeLimitExceeded =
                                    isTimeLimitExceeded retval,
                                timeLimit = Just tLimit,
                                proof_status = proof_status res_cfg,
                                resultOutput = resultOutput res_cfg})
                      prName (AS_Anno.senName nGoal)
                      (proof_tree s)
                      (configsMap s)}
  writeIORef stateRef s'

  let notReady = numGoals - processedGoalsSoFar > 0
  label # text (if notReady
                then (batchInfoText tLimit numGoals processedGoalsSoFar)
                else "Batch mode finished\n\n")

  return notReady

{- |
   Updates the display of the status of the current goal.
-}
updateDisplay :: GenericState sign sentence proof_tree pst
                 -- ^ current global prover state
              -> Bool -- ^ set to 'True' if you want the 'ListBox' to be updated
              -> ListBox String -- ^ 'ListBox' displaying the status of all goals (see 'goalsView')
              -> Label -- ^ 'Label' displaying the status of the currently selected goal (see 'toGuiStatus')
              -> Entry Int -- ^ 'Entry' containing the time limit of the current goal
              -> Entry String -- ^ 'Entry' containing the extra options
              -> ListBox String -- ^ 'ListBox' displaying all axioms used to prove a goal (if any)
              -> IO ()
updateDisplay st updateLb goalsLb statusLabel timeEntry optionsEntry axiomsLb = do
    when updateLb
         (populateGoalsListBox goalsLb (goalsView st))
    maybe (return ())
          (\ go ->
               let mprfst = Map.lookup go (configsMap st)
                   cf = Map.findWithDefault
                        (error "updateDisplay: configsMap \
                               \was not initialised!!")
                        go (configsMap st)
                   t' = maybe guiDefaultTimeLimit id (timeLimit cf)
                   opts' = unwords (extraOpts cf)
                   (color, label) = maybe statusOpen
                                    ((toGuiStatus cf) . proof_status)
                                    mprfst
                   usedAxs = maybe [] (usedAxioms . proof_status) mprfst

               in do
                statusLabel # text label
                statusLabel # foreground (show color)
                timeEntry # HTk.value t'
                optionsEntry # HTk.value opts'
                axiomsLb # HTk.value (usedAxs::[String])
                return ())
          (currentGoal st)

newOptionsFrame :: Container par =>
                par -- ^ the parent container
             -> (Entry Int -> Spin -> IO a)
             -- ^ Function called by pressing one spin button
             -> IO OpFrame
newOptionsFrame con updateFn = do
  right <- newFrame con []

  -- contents of newOptionsFrame
  l1 <- newLabel right [text "Options:"]
  pack l1 [Anchor NorthWest]
  opFrame <- newFrame right []
  pack opFrame [Expand On, Fill X, Anchor North]

  spacer <- newLabel opFrame [text "   "]
  pack spacer [Side AtLeft]

  opFrame2 <- newVBox opFrame []
  pack opFrame2 [Expand On, Fill X, Anchor NorthWest]

  timeLimitFrame <- newFrame opFrame2 []
  pack timeLimitFrame [Expand On, Fill X, Anchor West]

  l2 <- newLabel timeLimitFrame [text "TimeLimit"]
  pack l2 [Side AtLeft]

  -- extra HBox for time limit display
  timeLimitLine <- newHBox timeLimitFrame []
  pack timeLimitLine [Expand On, Side AtRight, Anchor East]

  (timeEntry :: Entry Int) <- newEntry timeLimitLine [width 18,
                                              HTk.value guiDefaultTimeLimit]
  pack timeEntry []

  timeSpinner <- newSpinButton timeLimitLine (updateFn timeEntry) []
  pack timeSpinner []

  l3 <- newLabel opFrame2 [text "Extra Options:"]
  pack l3 [Anchor West]
  (optionsEntry :: Entry String) <- newEntry opFrame2 [width 37]
  pack optionsEntry [Fill X, PadX (cm 0.1)]

  return $ OpFrame { of_Frame = right
                   , of_timeSpinner = timeSpinner
                   , of_timeEntry = timeEntry
                   , of_optionsEntry = optionsEntry}

-- ** Main GUI

{- |
  Invokes the prover GUI. Users may start the batch prover run on all goals,
  or use a detailed GUI for proving each goal manually.
-}
genericATPgui :: (Ord proof_tree, Ord sentence, Show proof_tree, Show sentence) =>
                 ATPFunctions sign sentence proof_tree pst -- ^ prover specific functions
              -> String -- ^ prover name
              -> String -- ^ theory name
              -> Theory sign sentence proof_tree -- ^ theory consisting of a signature and a list of Named sentence
              -> proof_tree
              -> IO([Proof_status proof_tree]) -- ^ proof status for each goal
genericATPgui atpFun prName thName th pt = do
  -- create initial backing data structure
  let initState = initialGenericState prName
                                      (initialProverState atpFun)
                                      (atpTransSenName atpFun) th pt
  stateRef <- newIORef initState
  batchTLimit <- getBatchTimeLimit $ batchTimeEnv atpFun

  -- main window
  main <- createToplevel [text $ thName ++ " - " ++ prName ++ " Prover"]
  pack main [Expand On, Fill Both]

  -- VBox for the whole window
  b <- newVBox main []
  pack b [Expand On, Fill Both]

  -- HBox for the upper part (goals on the left, options/results on the right)
  b2 <- newHBox b []
  pack b2 [Expand On, Fill Both]

  -- left frame (goals)
  left <- newFrame b2 []
  pack left [Expand On, Fill Both]

  b3 <- newVBox left []
  pack b3 [Expand On, Fill Both]

  l0 <- newLabel b3 [text "Goals:"]
  pack l0 [Anchor NorthWest]

  lbFrame <- newFrame b3 []
  pack lbFrame [Expand On, Fill Both]

  lb <- newListBox lbFrame [bg "white",exportSelection False,
                            selectMode Single, height 15] :: IO (ListBox String)
  populateGoalsListBox lb (goalsView initState)
  pack lb [Expand On, Side AtLeft, Fill Both]
  sb <- newScrollBar lbFrame []
  pack sb [Expand On, Side AtRight, Fill Y, Anchor West]
  lb # scrollbar Vertical sb

  -- right frame (options/results)
  OpFrame { of_Frame = right
          , of_timeSpinner = timeSpinner
          , of_timeEntry = timeEntry
          , of_optionsEntry = optionsEntry}
      <- newOptionsFrame b2
                 (\ timeEntry sp -> synchronize main
                   (do
               s <- readIORef stateRef
               maybe noGoalSelected
                     (\ goal ->
                      do
                      curEntTL <- getValueSafe guiDefaultTimeLimit timeEntry
                      let sEnt = s {configsMap =
                                        adjustOrSetConfig
                                             (setTimeLimit curEntTL)
                                             prName goal pt (configsMap s)}
                          cfg = getConfig prName goal pt (configsMap sEnt)
                          t = timeLimit cfg
                          t' = (case sp of
                                Up -> maybe (guiDefaultTimeLimit + 10)
                                            (+10)
                                            t
                                _ -> maybe (guiDefaultTimeLimit - 10)
                                            (\ t1 -> t1-10)
                                            t)
                          s' = sEnt {configsMap =
                                         adjustOrSetConfig
                                              (setTimeLimit t')
                                              prName goal pt (configsMap sEnt)}
                      writeIORef stateRef s'
                      timeEntry # HTk.value
                                    (maybe guiDefaultTimeLimit
                                           id
                                           (timeLimit $
                                              getConfig prName goal pt $
                                                configsMap s'))
                      done)
                     (currentGoal s)))
  pack right [Expand On, Fill Both, Anchor NorthWest]

  -- buttons for options
  buttonsHb1 <- newHBox right []
  pack buttonsHb1 [Anchor NorthEast]

  saveDFGButton <- newButton buttonsHb1 [text "Save DFG File"]
  pack saveDFGButton [Side AtLeft]
  proveButton <- newButton buttonsHb1 [text "Prove"]
  pack proveButton [Side AtRight]

  -- result frame
  resultFrame <- newFrame right []
  pack resultFrame [Expand On, Fill Both]

  l4 <- newLabel resultFrame [text "Results:"]
  pack l4 [Anchor NorthWest]

  spacer <- newLabel resultFrame [text "   "]
  pack spacer [Side AtLeft]

  resultContentBox <- newHBox resultFrame []
  pack resultContentBox [Expand On, Anchor West, Fill Both]

  -- labels on the left side
  rc1 <- newVBox resultContentBox []
  pack rc1 [Expand Off, Anchor North]
  l5 <- newLabel rc1 [text "Status"]
  pack l5 [Anchor West]
  l6 <- newLabel rc1 [text "Used Axioms"]
  pack l6 [Anchor West]

  -- contents on the right side
  rc2 <- newVBox resultContentBox []
  pack rc2 [Expand On, Fill Both, Anchor North]

  statusLabel <- newLabel rc2 [text " -- "]
  pack statusLabel [Anchor West]
  axiomsFrame <- newFrame rc2 []
  pack axiomsFrame [Expand On, Anchor West, Fill Both]
  axiomsLb <- newListBox axiomsFrame [HTk.value $ ([]::[String]),
                                      bg "white",exportSelection False,
                                      selectMode Browse,
                                      height 6, width 19] :: IO (ListBox String)
  pack axiomsLb [Side AtLeft, Expand On, Fill Both]
  axiomsSb <- newScrollBar axiomsFrame []
  pack axiomsSb [Side AtRight, Fill Y, Anchor West]
  axiomsLb # scrollbar Vertical axiomsSb

  detailsButton <- newButton resultFrame [text "Show Details"]
  pack detailsButton [Anchor NorthEast]

  -- separator
  sp1 <- newSpace b (cm 0.15) []
  pack sp1 [Expand Off, Fill X, Side AtBottom]

  newHSeparator b

  sp2 <- newSpace b (cm 0.15) []
  pack sp2 [Expand Off, Fill X, Side AtBottom]

  -- batch mode frame
  batch <- newFrame b []
  pack batch [Expand Off, Fill X]

  batchTitle <- newLabel batch [text $ (prName)++" Batch Mode:"]
  pack batchTitle [Side AtTop]

  batchLeft <- newVBox batch []
  pack batchLeft [Expand On, Fill X, Side AtLeft]

  batchBtnBox <- newHBox batchLeft []
  pack batchBtnBox [Expand On, Fill X, Side AtLeft]
  stopBatchButton <- newButton batchBtnBox [text "Stop"]
  pack stopBatchButton []
  runBatchButton <- newButton batchBtnBox [text "Run"]
  pack runBatchButton []

  batchSpacer <- newSpace batchLeft (pp 150) [orient Horizontal]
  pack batchSpacer [Side AtLeft]
  batchStatusLabel <- newLabel batchLeft [text "\n\n"]
  pack batchStatusLabel []

  OpFrame { of_Frame = batchRight
          , of_timeSpinner = batchTimeSpinner
          , of_timeEntry = batchTimeEntry
          , of_optionsEntry = batchOptionsEntry}
      <- newOptionsFrame batch
                 (\ tEntry sp -> synchronize main
                   (do
                    curEntTL <- getValueSafe batchTLimit tEntry
                    let t' = case sp of
                              Up -> curEntTL+10
                              _ -> max batchTLimit (curEntTL-10)
                    tEntry # HTk.value t'
                    done))

  pack batchRight [Expand On, Fill X, Anchor NorthWest,Side AtRight]

  batchTimeEntry # HTk.value batchTLimit

  -- separator 2
  sp1_2 <- newSpace b (cm 0.15) []
  pack sp1_2 [Expand Off, Fill X, Side AtBottom]

  newHSeparator b

  sp2_2 <- newSpace b (cm 0.15) []
  pack sp2_2 [Expand Off, Fill X, Side AtBottom]

  -- global options frame
  globalOptsFr <- newFrame b []
  pack globalOptsFr [Expand Off, Fill Both]

  gOptsTitle <- newLabel globalOptsFr [text "Global Options:"]
  pack gOptsTitle [Side AtTop]

  inclProvedThsTK <- createTkVariable True
  inclProvedThsCheckButton <-
         newCheckButton globalOptsFr
                        [variable inclProvedThsTK,
                         text ("include preceeding proven therorems"++
                               " in next proof attempt")]
  pack inclProvedThsCheckButton [Side AtLeft]

  -- separator 3
  sp1_3 <- newSpace b (cm 0.15) []
  pack sp1_3 [Expand Off, Fill X, Side AtBottom]

  newHSeparator b

  sp2_3 <- newSpace b (cm 0.15) []
  pack sp2_3 [Expand Off, Fill X, Side AtBottom]

  -- bottom frame (help/save/exit buttons)
  bottom <- newHBox b []
  pack bottom [Expand Off, Fill Both]

  helpButton <- newButton bottom [text "Help"]
  pack helpButton [PadX (cm 0.3), IPadX (cm 0.1)]  -- wider "Help" button
  saveButton <- newButton bottom [text "Save Prover Configuration"]
  pack saveButton [PadX (cm 0.3)]
  exitButton <- newButton bottom [text "Exit Prover"]
  pack exitButton [PadX (cm 0.3)]

  putWinOnTop main

  -- IORef for batch thread
  threadStateRef <- newIORef initialThreadState

  -- events
  (selectGoal, _) <- bindSimple lb (ButtonPress (Just 1))
  doProve <- clicked proveButton
  saveDFG <- clicked saveDFGButton
  showDetails <- clicked detailsButton

  runBatch <- clicked runBatchButton
  stopBatch <- clicked stopBatchButton

  help <- clicked helpButton
  saveConfiguration <- clicked saveButton
  exit <- clicked exitButton

  (closeWindow,_) <- bindSimple main Destroy

  let goalSpecificWids = [EnW timeEntry, EnW timeSpinner,EnW optionsEntry] ++
                         map EnW [proveButton,detailsButton,saveDFGButton]
      wids = EnW lb : goalSpecificWids ++
             [EnW batchTimeEntry, EnW batchTimeSpinner,
              EnW batchOptionsEntry,EnW inclProvedThsCheckButton] ++
             map EnW [helpButton,saveButton,exitButton,runBatchButton]

  disableWids goalSpecificWids
  disable stopBatchButton

  -- event handlers
  spawnEvent
    (forever
      ((selectGoal >>> do
          s <- readIORef stateRef
          let oldGoal = currentGoal s
          curEntTL <- (getValueSafe guiDefaultTimeLimit timeEntry) :: IO Int
          let s' = maybe s
                         (\ og -> s
                             {configsMap =
                                  adjustOrSetConfig (setTimeLimit curEntTL)
                                                    prName og pt
                                                    (configsMap s)})
                         oldGoal
          sel <- (getSelection lb) :: IO (Maybe [Int])
          let s'' = maybe s' (\ sg -> s' {currentGoal =
                                              Just $ AS_Anno.senName
                                               (goalsList s' !! head sg)})
                             sel
          writeIORef stateRef s''
          when (isJust sel && not (batchModeIsRunning s''))
               (enableWids goalSpecificWids)
          when (isJust sel) $ enableWids [EnW detailsButton,EnW saveDFGButton]
          updateDisplay s'' False lb statusLabel timeEntry optionsEntry axiomsLb
          done)
      +> (saveDFG >>> do
            rs <- readIORef stateRef
            inclProvedThs <- readTkVariable inclProvedThsTK
            maybe (return ())
                  (\ goal -> do
                      let (nGoal,lp') =
                              prepareLP (proverState rs)
                                        rs goal inclProvedThs
                      prob <- (dfgOutput atpFun) lp' nGoal
                      createTextSaveDisplay (prName++" Problem for Goal "++goal)
                                            (thName++goal++".dfg")
                                            (prob)
                  )
                  $ currentGoal rs
            done)
      +> (doProve >>> do
            rs <- readIORef stateRef
            if isNothing $ currentGoal rs
              then noGoalSelected
              else (do
                curEntTL <- (getValueSafe guiDefaultTimeLimit
                                          timeEntry) :: IO Int
                inclProvedThs <- readTkVariable inclProvedThsTK
                let goal = fromJust $ currentGoal rs
                    s = rs {configsMap = adjustOrSetConfig
                                            (setTimeLimit curEntTL)
                                            prName goal pt
                                            (configsMap rs)}
                    (nGoal,lp') = prepareLP (proverState rs)
                                        rs goal inclProvedThs
                extraOptions <- (getValue optionsEntry) :: IO String
                let s' = s {configsMap = adjustOrSetConfig
                                            (setExtraOpts (words extraOptions))
                                            prName goal pt
                                            (configsMap s)}
                statusLabel # text (snd statusRunning)
                statusLabel # foreground (show $ fst statusRunning)
                disableWids wids
                (retval, cfg) <-
                    (runProver atpFun) lp'
                          (getConfig prName goal pt $ configsMap s')
                          thName nGoal
                -- check if main is still there
                curSt <- readIORef stateRef
                if mainDestroyed curSt
                    then done
                    else do
                 enableWids wids
                 case retval of
                   ATPError message -> errorMess message
                   _ -> return ()
                 let s'' = s'{
                     configsMap =
                        adjustOrSetConfig
                           (\ c -> c {timeLimitExceeded = isTimeLimitExceeded retval,
                                      proof_status = proof_status cfg,
                                      resultOutput = resultOutput cfg})
                           prName goal pt (configsMap s')}
                 writeIORef stateRef s''
                 updateDisplay s'' True lb statusLabel timeEntry
                              optionsEntry axiomsLb
                 done)
            done)
      +> (showDetails >>> do
            s <- readIORef stateRef
            if isNothing $ currentGoal s
              then noGoalSelected
              else (do
                let goal = fromJust $ currentGoal s
                let result = Map.lookup goal (configsMap s)
                let output = if isJust result
                               then resultOutput (fromJust result)
                               else ["This goal hasn't been run through "++
                                     "the prover yet."]
                let detailsText = concatMap ('\n':) output
                createTextSaveDisplay (prName ++ " Output for Goal "++goal)
                                      (goal ++ (fst $ fileExtensions atpFun))
                                      (seq (length detailsText) detailsText)
                done)
            done)
      +> (runBatch >>> do
            cleanupThread threadStateRef
            s <- readIORef stateRef
            -- get options for this batch run
            curEntTL <- (getValueSafe batchTLimit batchTimeEntry) :: IO Int
            let tLimit = if curEntTL > 0 then curEntTL else batchTLimit
            batchTimeEntry # HTk.value tLimit
            extOpts <- (getValue batchOptionsEntry) :: IO String
            writeIORef stateRef (s {batchModeIsRunning = True})
            let numGoals = Map.size $ filterOpenGoals $ configsMap s
            if numGoals > 0
             then do
              batchStatusLabel # text (batchInfoText tLimit numGoals 0)
              disableWids wids
              enable stopBatchButton
              enableWidsUponSelection lb [EnW detailsButton,EnW saveDFGButton]
              enable lb
              inclProvedThs <- readTkVariable inclProvedThsTK
              batchProverId <- Concurrent.forkIO
                   (do genericProveBatch tLimit extOpts inclProvedThs
                          (\ gPSF nSen cfg -> do
                              cont <- goalProcessed stateRef tLimit numGoals
                                                    batchStatusLabel
                                                    prName gPSF nSen cfg
                              st <- readIORef stateRef
                              updateDisplay st True lb statusLabel timeEntry
                                            optionsEntry axiomsLb
                              when (not cont)
                                   (do
                                    -- putStrLn "Batch ended"
                                    disable stopBatchButton
                                    enableWids wids
                                    enableWidsUponSelection lb goalSpecificWids
                                    writeIORef stateRef
                                            (st {batchModeIsRunning = False})
                                    cleanupThread threadStateRef)
                              return cont)
                          (atpInsertSentence atpFun) (runProver atpFun)
                          prName thName s
                       return ())
              modifyIORef threadStateRef
                        (\ ts -> ts{batchId = Just batchProverId})
              done
             else do
              batchStatusLabel # text ("No further open goals\n\n")
              done)
      +> (stopBatch >>> do
            cleanupThread threadStateRef
            modifyIORef threadStateRef (\ s -> s {batchStopped = True})
            -- putStrLn "Batch stopped"
            disable stopBatchButton
            enableWids wids
            enableWidsUponSelection lb goalSpecificWids
            batchStatusLabel # text "Batch mode stopped\n\n"
            st <- readIORef stateRef
            writeIORef stateRef
                           (st {batchModeIsRunning = False})
            updateDisplay st True lb statusLabel timeEntry
                          optionsEntry axiomsLb
            done)
      +> (help >>> do
            createTextDisplay (prName ++ " Help")
                              (proverHelpText atpFun)
                              [size (80, 30)]
            done)
      +> (saveConfiguration >>> do
            s <- readIORef stateRef
            let (cfgList, resList) = getCfgText $ configsMap s
                cfgText = unlines $ ("Configuration:\n":cfgList)
                                    ++ ("\nResults:\n":resList)
            createTextSaveDisplay (prName ++ " Configuration for Theory " ++ thName)
                                  (thName ++ (snd $ fileExtensions atpFun)) cfgText
            done)
      ))
  sync ( (exit >>> destroy main)
      +> (closeWindow >>> do cleanupThread threadStateRef
                             modifyIORef stateRef
                                         (\ s -> s{mainDestroyed = True})
                             destroy main)
       )
  s <- readIORef stateRef
  let proof_stats = map (\g -> let res = Map.lookup g (configsMap s)
                                   g' = Map.findWithDefault
                                        (error ("Lookup of name failed: (1) "
                                                ++"should not happen \""
                                                ++g++"\""))
                                        g (namesMap s)
                                   pStat = proof_status $ fromJust res
                               in if isJust res
                                  then transNames (namesMap s) pStat
                                  else openProof_status g' prName $
                                       proof_tree s)
                    (map AS_Anno.senName $ goalsList s)
  return proof_stats

  where
    cleanupThread tRef = do
         st <- readIORef tRef
         -- cleaning up
         maybe (return ())
               (\ tId -> do
                   Concurrent.killThread tId
                   writeIORef tRef initialThreadState)
               (batchId st)

    noGoalSelected = errorMess "Please select a goal first."
    prepareLP prS s goal inclProvedThs =
       let (beforeThis, afterThis) =
               splitAt (fromJust $
                        findIndex (\sen -> AS_Anno.senName sen == goal)
                                  (goalsList s))
                       (goalsList s)
           proved = filter (\sen-> checkGoal (configsMap s)
                                       (AS_Anno.senName sen)) beforeThis
       in if inclProvedThs
             then (head afterThis,
                   foldl (\lp provedGoal ->
                     (atpInsertSentence atpFun)
                       lp (provedGoal{AS_Anno.isAxiom = True}))
                         prS
                         (reverse proved))
             else (maybe (error ("GUI.GenericATP.prepareLP: Goal "++goal++
                                 " not found!!"))
                         id (find ((==goal) . AS_Anno.senName) (goalsList s)),
                   prS)
    getCfgText mp = ("{":lc, "{":lr)
      where
      (lc, lr) =
        Map.foldWithKey (\ k cfg (lCfg,lRes) ->
                           let r = proof_status cfg
                               outp = resultOutput cfg
                           in
                           ((show k
                             ++ ":=GenericConfig {"
                             ++ "timeLimit = " ++ show (timeLimit cfg)
                             ++ ", timeLimitExceeded = "
                             ++ show (timeLimitExceeded cfg)
                             ++ ", extraOpts = "
                             ++ show (extraOpts cfg)
                             ++ "}," ):lCfg,
                            (show k
                             ++ ":=\n    ("
                             ++ show r ++ ",\n     \""
                             ++ (unlines outp) ++ "\")"):lRes))
                        (["}"],["}"]) mp
    transNames nm pStat =
      pStat { goalName = trN $ goalName pStat
            , usedAxioms = foldr (fil $ trN $ goalName pStat) [] $
                           usedAxioms pStat }
      where trN x' = Map.findWithDefault
                      (error ("Lookup of name failed: (2) "++
                              "should not happen \""++x'++"\""))
                      x' nm
            fil g ax axs =
                maybe (trace ("*** "++prName++" Warning: unknown axiom \""++
                              ax++"\" omitted from list of used\n"++
                              "      axioms of goal \""++g++"\"")
                                axs) (:axs) (Map.lookup ax nm)


-- * Non-interactive Batch Prover

-- ** Constants

{- |
  Time limit used by the batch mode prover.
-}
batchTimeLimit :: Int
batchTimeLimit = 20

-- ** Utility Functions

{- |
  reads passed ENV-variable and if it exists and has an Int-value this value is returned otherwise the value of 'batchTimeLimit' is returned.
-}

getBatchTimeLimit :: String -- ^ ENV-variable containing batch time limit
                  -> IO Int
getBatchTimeLimit env = do
   is <- Exception.catch (getEnv env)
               (\e -> case e of
                      Exception.IOException ie ->
                          if isDoesNotExistError ie -- == NoSuchThing
                          then return $ show batchTimeLimit
                          else Exception.throwIO e
                      _ -> Exception.throwIO e)
   return (either (const batchTimeLimit) id (readEither is))

{- |
  Checks whether a goal in the results map is marked as proved.
-}
checkGoal :: GenericConfigsMap proof_tree -> ATPIdentifier -> Bool
checkGoal cfgMap goal =
  isJust g && isProvedStat (proof_status $ fromJust g)
  where
    g = Map.lookup goal cfgMap


-- ** Implementation

{- |
  A non-GUI batch mode prover. The list of goals is processed sequentially.
  Proved goals are inserted as axioms.
-}
genericProveBatch :: (Ord proof_tree) =>
                     Int -- ^ batch time limit
                  -> String -- ^ extra options passed
                  -> Bool -- ^ True means include proved theorems
                  -> (Int
                      -> AS_Anno.Named sentence
                      -> (ATPRetval, GenericConfig proof_tree)
                      -> IO Bool)
                      -- ^ called after every prover run.
                      -- return True if you want the prover to continue.
                  -> (pst -> AS_Anno.Named sentence -> pst)
                      -- ^ inserts a Namend sentence into a logicalPart
                  -> RunProver sentence proof_tree pst -- prover to run batch
                  -> String -- ^ prover name
                  -> String -- ^ theory name
                  -> GenericState sign sentence proof_tree pst
                  -> IO ([Proof_status proof_tree]) -- ^ proof status for each goal
genericProveBatch tLimit extraOptions inclProvedThs f inSen runGivenProver
                  prName thName st =
    batchProve (proverState st) 0 [] (goalsList st)
  {- do -- putStrLn $ showPretty initialLogicalPart ""
     -- read batchTimeLimit from ENV variable if set otherwise use constant
     pstl <- {- trace (showPretty initialLogicalPart (show goals)) -}
             batchProve (initialLogicalPart st) [] (goalsList st)
     -- putStrLn ("Outcome of proofs:\n" ++ unlines (map show pstl) ++ "\n")
     return pstl -}
  where
    openGoals = filterOpenGoals (configsMap st)

    addToLP g res pst =
        if isProvedStat res && inclProvedThs
        then inSen pst (g{AS_Anno.isAxiom = True})
        else pst
    batchProve _ _ resDone [] = return (reverse resDone)
    batchProve pst goalsProcessedSoFar resDone (g:gs) =
     let gName = AS_Anno.senName g
         pt    = proof_tree st
     in
      if Map.member gName openGoals
      then do
        putStrLn $ "Trying to prove goal: " ++ gName
        -- putStrLn $ show g
        (err, res_cfg) <-
              runGivenProver pst ((emptyConfig prName gName pt)
                                   { timeLimit = Just tLimit
                                   , extraOpts = words extraOptions })
                             thName g
        let res = proof_status res_cfg
        putStrLn $ prName ++ " returned: " ++ (show err)
        -- if the batch prover runs in a separate thread
        -- that's killed via killThread
        -- runGivenProver will return ATPError. We have to stop the
        -- recursion in that case
        case err of
          ATPError _ -> return ((reverse (res:resDone)) ++
                                (map (\ gl -> openProof_status
                                                (AS_Anno.senName gl) prName pt)
                                     gs))
          _ -> do
               -- add proved goals as axioms
              let pst' = addToLP g res pst
                  goalsProcessedSoFar' = goalsProcessedSoFar+1
              cont <- f goalsProcessedSoFar' g (err, res_cfg)
              if cont
                 then batchProve pst' goalsProcessedSoFar' (res:resDone) gs
                 else return ((reverse (res:resDone)) ++
                                (map (\ gl -> openProof_status
                                                (AS_Anno.senName gl) prName pt)
                                     gs))
      else batchProve (addToLP g (proof_status $
                                  Map.findWithDefault (emptyConfig prName gName pt)
                                     gName $ configsMap st)
                               pst)
                      goalsProcessedSoFar resDone gs
