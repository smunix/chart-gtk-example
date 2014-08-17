{-# OPTIONS_GHC -Wall #-}
{-# Language ScopedTypeVariables #-}
{-# Language DeriveFunctor #-}
{-# Language PackageImports #-}

module Main
       ( main
       ) where

import Control.Monad ( forever )
import qualified Control.Concurrent as CC
import "gtk" Graphics.UI.Gtk ( AttrOp( (:=) ) )
import qualified "gtk" Graphics.UI.Gtk as Gtk
import Control.Lens ( (.~) )
import Data.Default.Class ( def )
import qualified Graphics.Rendering.Chart as Chart
import Graphics.Rendering.Chart.Backend.Cairo ( runBackend, defaultEnv )


animationWaitTime :: Int
animationWaitTime = 33 -- i think this means 1/33 =~= 30.3 Hz

main :: IO ()
main = do
  -- have to call this before any other gtk stuff
  _ <- Gtk.initGUI

  -- the main window
  win <- Gtk.windowNew
  _ <- Gtk.set win [ Gtk.containerBorderWidth := 8
                   , Gtk.windowTitle := "wooooooooooo"
                   ]

  -- lets have a little fun, make a little label widget to display a message for us
  msg <- Gtk.labelNew (Just "..... heeeeey macarena ..... lol ..... lol ..... lol ..... lol ")

  -- a little worker to update the message
  let msgUpdater = do
        CC.threadDelay 200000 -- 1/5 second delay
        -- have to call postGUISync because gtk is not thread-safe
        Gtk.postGUISync $ do
          (x0:xs) <- Gtk.labelGetText msg :: IO String
          Gtk.labelSetText msg (xs ++ [x0])

  -- fork that worker thread
  msgThread <- CC.forkIO $ forever msgUpdater

  -- a worker thread to update whatever will be plotted
  -- use an MVar as an abstraction barrier
  -- for now just keep shifting the data in time
  plotData <- CC.newMVar $ unzip [(t, sin(t)) | t <- init [0,0.05..2*pi :: Double]]
  let shiftData (xs,y0:ys) = (xs, ys ++ [y0])
      shiftData _ = ([],[])
      dataUpdater = do
        CC.threadDelay 50000 -- 20Hz
        CC.modifyMVar_ plotData (return . shiftData)
  -- fork the worker thread
  plotDataThread <- CC.forkIO $ forever dataUpdater

  -- When the window is destroyed, kill the message thread and quit Gtk.
  -- I think this is only important in GHCI or other cases you want to
  -- repeatedly start/stop the gui in a single process.
  _ <- Gtk.onDestroy win $ do
    CC.killThread msgThread
    CC.killThread plotDataThread
    Gtk.mainQuit

  -- create the other widget, the main plotter
  plotArea <- newChartCanvas plotData

  -- create a box which will contain the message widget and plot widget
  vbox <- Gtk.vBoxNew False 4
  -- add the children
  Gtk.set vbox $
    [ Gtk.containerChild := msg
    , Gtk.boxChildPacking msg := Gtk.PackNatural
    , Gtk.containerChild := plotArea
    , Gtk.boxChildPacking plotArea := Gtk.PackNatural
    ]

  -- Set the child of the main window
  -- We have to use the vbox because the main window can only have 1 child
  _ <- Gtk.set win [ Gtk.containerChild := vbox ]

  -- show the main window and start the gtk loop
  Gtk.widgetShowAll win
  Gtk.mainGUI

newChartCanvas :: (Chart.PlotValue a, Show a, RealFloat a)
                  => CC.MVar ([a],[a]) -> IO Gtk.DrawingArea
newChartCanvas plotData = do
  -- chart drawing area
  chartCanvas <- Gtk.drawingAreaNew
  _ <- Gtk.widgetSetSizeRequest chartCanvas 250 250
  _ <- Gtk.onExpose chartCanvas $ const (updateCanvas chartCanvas plotData)
  -- this is a delay which makes it periodically redraw
  _ <- Gtk.timeoutAddFull
       (Gtk.widgetQueueDraw chartCanvas >> return True)
       Gtk.priorityDefaultIdle animationWaitTime
  return chartCanvas


-- this reads the data MVar and plots whatever is in it
updateCanvas :: (Chart.PlotValue a, Show a, RealFloat a)
                => Gtk.DrawingArea -> CC.MVar ([a],[a]) -> IO Bool
updateCanvas canvas plotData = do
  points <- CC.readMVar plotData

  let myGraph = displayChart (uncurry zip points)
  chartGtkUpdateCanvas myGraph canvas


-- this is the function which turns a list of points into a Chart
displayChart :: forall a . (Chart.PlotValue a, Show a, RealFloat a)
                => [(a,a)] -> Chart.Renderable ()
displayChart points = Chart.toRenderable layout
  where
    drawOne (name,pc) col
      = Chart.plot_lines_values .~ pc
        $ Chart.plot_lines_style  . Chart.line_color .~ col
--        $ Chart.plot_points_style ~. Chart.filledCircles 2 red
        $ Chart.plot_lines_title .~ name
        $ def
    allLines = zipWith drawOne
               [("hi",[points]),("there", [map (\(x,y) -> (x,y+0.5)) points])]
               Chart.defaultColorSeq

    xlabel = "I am an X label, hear me roar"

    layout = Chart.layout_plots .~ map Chart.toPlot allLines
             $ Chart.layout_title .~ "Wooo, Party Graph!"
             $ Chart.layout_x_axis . Chart.laxis_title .~ xlabel
             $ def

-- this is also available in the Charg-gtk package as "updateCanvas"
chartGtkUpdateCanvas :: Chart.Renderable a -> Gtk.DrawingArea  -> IO Bool
chartGtkUpdateCanvas chart canvas = do
    win <- Gtk.widgetGetDrawWindow canvas
    (width, height) <- Gtk.widgetGetSize canvas
    regio <- Gtk.regionRectangle $ Gtk.Rectangle 0 0 width height
    let sz = (fromIntegral width,fromIntegral height)
    Gtk.drawWindowBeginPaintRegion win regio
    _ <- Gtk.renderWithDrawable win $ runBackend (defaultEnv Chart.bitmapAlignmentFns) (Chart.render chart sz) 
    Gtk.drawWindowEndPaint win
    return True

