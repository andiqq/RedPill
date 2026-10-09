// This file is part of Red Pill
// A 3D OpenGL "Matrix" screensaver for Mac OS X
// Copyright (C) 2002, 2003 mathew <meta@pobox.com>
//
// Red Pill is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program; if not, write to the Free Software
// Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307  USA
// or visit <URL:http://www.fsf.org/>

#import "MatrixView.h"
#import <AppKit/AppKit.h>
#import <AppKit/NSAttributedString.h>
#import "MatrixMacros.h"
#import "MatrixStripParams.h"

@implementation MatrixView

// Posted by the system when the screensaver is dismissed. On recent macOS versions
// the host process often never calls stopAnimation, and keeps old instances alive.
#define SCREENSAVER_WILL_STOP_NOTIFICATION @"com.apple.screensaver.willstop"

// Read a preference, clamped to the range the preferences sheet allows
static float ClampedDefault(ScreenSaverDefaults *defaults, NSString *key, float lo, float hi)
{
   float v = [defaults floatForKey:key];
   // fmaxf also turns NaN into lo
   return fminf(fmaxf(v, lo), hi);
}

/// SECTION ONE
/// Core ScreenSaverView method implementations

// Constructor to initialize a screensaver in the specified rectangular frame.
// The frame may be a full screen, or a preview window.
- (instancetype)initWithFrame:(NSRect)frame isPreview:(BOOL)previewmode
{
NSOpenGLPixelFormatAttribute attributes[] = {
   NSOpenGLPFAAccelerated,
   NSOpenGLPFADoubleBuffer,
   NSOpenGLPFAAllowOfflineRenderers,
   NSOpenGLPFAColorSize, 24,
   NSOpenGLPFAAlphaSize, 8,
   (NSOpenGLPixelFormatAttribute)0};
NSOpenGLPixelFormatAttribute fallbackAttributes[] = {
   NSOpenGLPFADoubleBuffer,
   NSOpenGLPFAColorSize, 24,
   (NSOpenGLPixelFormatAttribute)0};
NSOpenGLPixelFormat *pixformat;
GLint swapInterval = 1;
GLint surfaceOpacity = 1;

   isPreview = previewmode;
   // Initialize the superclass to set up the environment for the screensaver
   self = [super initWithFrame:frame isPreview:isPreview];
   if (self == nil) {
      LogError("initWithFrame", "Failed to initialize screensaver environment. Not my fault.");
      return nil;
   }

   // Work out what our defaults are called
   NSBundle *bundle = [NSBundle bundleForClass:[self class]];
   NSString *identifier = [bundle bundleIdentifier];
   if(identifier == nil) {
      LogError("initWithFrame", "Trying to initialize preferences but identifier is nil!");
      return nil;
   }
   ScreenSaverDefaults *defaults = [ScreenSaverDefaults defaultsForModuleWithName:identifier];
   // Create and register an array of "default defaults"
   // Note that since the screensaver parameters are mostly between 0 and something < 1 internally,
   // and UI sliders only have a resolution of 0.1, we multiply 'em all by 100, so 0.15 becomes 15.
   NSDictionary *defdefs = @{STRIPS_KEY: STRIPS_DEFAULT,
      VELOCITY_KEY: VELOCITY_DEFAULT,
      DEPTH_KEY: DEPTH_DEFAULT,
      CYCLING_KEY: CYCLING_DEFAULT,
      FALLING_KEY: FALLING_DEFAULT,
      CURSOR_KEY: CURSOR_DEFAULT,
      FOG_KEY: FOG_DEFAULT,
      TOPSTART_KEY: TOPSTART_DEFAULT,
      MAINONLY_KEY: MAINONLY_DEFAULT,
      SPOON_KEY: SPOON_DEFAULT};
   [defaults registerDefaults:defdefs];
   // Now load either those defaults, or the user's prior choice of preferences
   [self loadDefaults:nil];

   // We find out which screen we're on once we have a window; until then assume main
   isMainScreen = TRUE;
   // If we're running in preview mode, we need to set up a notification so the preferences dialog
   // can tell us when we need to reload our parameters to show the changes.
   // Note that the notification center should always be set up, otherwise it's possible to cause
   // race conditions that result in a crash by clicking buttons quickly and repeatedly.
   [[NSNotificationCenter defaultCenter]
      addObserver:self
         selector:@selector(loadDefaults:)
             name:PREFS_NOTIFICATION
           object:nil];
   // Make sure we stop drawing (and free the GPU) when the screensaver is dismissed,
   // even if the system forgets to call stopAnimation
   if (!isPreview) {
      [[NSDistributedNotificationCenter defaultCenter]
         addObserver:self
            selector:@selector(screenSaverWillStop:)
                name:SCREENSAVER_WILL_STOP_NOTIFICATION
              object:nil];
   }

   // Create pixel format, falling back to something more basic if need be
   pixformat = [[NSOpenGLPixelFormat alloc] initWithAttributes:attributes];
   if (!pixformat) {
      pixformat = [[NSOpenGLPixelFormat alloc] initWithAttributes:fallbackAttributes];
   }
   if (!pixformat) {
      LogError("initWithFrame", "Failed to create a suitable pixel format. Your graphics card can't cope with this screensaver, sorry.");
      return nil;
   }

   // Create the GL view, filling our whole area and following our size
   glview = [[MatrixOpenGLView alloc] initWithFrame:[self bounds] pixelFormat:pixformat];
   if (glview == nil) {
      LogError("initWithFrame", "Failed to initialize OpenGL. Not my fault.");
      return nil;
   }
   [glview setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
   // Render at full resolution on Retina displays
   [glview setWantsBestResolutionOpenGLSurface:YES];
   [glview setRenderer:self];
   // Sync buffer swaps to the display refresh, to avoid tearing, and keep the surface opaque
   [[glview openGLContext] setValues:&swapInterval forParameter:NSOpenGLContextParameterSwapInterval];
   [[glview openGLContext] setValues:&surfaceOpacity forParameter:NSOpenGLContextParameterSurfaceOpacity];
   // We do the actual glFoo initialization calls later
   didGLinit = FALSE;
   // Make the GL context a subview of us
   [self addSubview:glview];
   // Set the animation speed
   [self setAnimationTimeInterval:1/30.0];
   // Initialize the parameters which aren't editable in the dialog box.
   // The idea is to parameterize everything in advance, so that you can
   // change what's editable in the dialog without too much pain.
   saverParams.cellSize = 2.0;
   saverParams.maxCellLife = 120;
   saverParams.numGlyphs = NUM_GLYPHS;
   saverParams.cursorChangeProbability = 20;
   saverParams.cursorLiveProbability = 30;
   saverParams.cursorStaticProbability = 30;
   saverParams.cursorEmptyProbability = 10;
   saverParams.framesPerLivingCellChange = 3;
   saverParams.minDepth = CLIP_NEAR;
   saverParams.spawnChance = 0.2;
   return self;
}

// Handle a change of preferences/configuration
- (void)loadDefaults:(NSNotification *) n
{
   // Work out what our defaults are called
   NSString *identifier = [[NSBundle bundleForClass:[self class]] bundleIdentifier];
   if(identifier == nil) {
      LogError("loadDefaults", "Trying to load preferences but identifier is nil.");
      return;
   }
   // Load defaults
   ScreenSaverDefaults *defaults = [ScreenSaverDefaults defaultsForModuleWithName:identifier];
   // Scale the values appropriately and set the saver parameters.
   // Values are clamped to the slider ranges, so a damaged preferences file can't break the animation.
   saverParams.maxStrips = (int)ClampedDefault(defaults, STRIPS_KEY, 1, 200);
   saverParams.driftSpeed = ClampedDefault(defaults, VELOCITY_KEY, 0, 80) / 100.0;
   saverParams.maxDepth = ClampedDefault(defaults, DEPTH_KEY, 80, CLIP_FAR);
   saverParams.colorCycleSpeed = ClampedDefault(defaults, CYCLING_KEY, 0, 10) / 100.0;
   saverParams.colorFallSpeed = ClampedDefault(defaults, FALLING_KEY, 0, 5) / 100.0;
   saverParams.cursorSpeed = ClampedDefault(defaults, CURSOR_KEY, 0, 60) / 100.0;
   saverParams.fogDensity = ClampedDefault(defaults, FOG_KEY, 0, 30) / 100.0;
   saverParams.minStartY = ([defaults boolForKey:TOPSTART_KEY] ? 1.0 : 0.0);
   mainScreenOnly = [defaults boolForKey:MAINONLY_KEY];
   // Fog is switched on or off as each frame is drawn
}

// Work out if we're running on the main display.
// This lets us offer a "run on main screen only" option for when OpenGL doesn't like running two monitors
- (void)updateIsMainScreen
{
   NSScreen *screen = [[self window] screen];
   NSScreen *mainScreen = [[NSScreen screens] firstObject];
   isMainScreen = (isPreview || screen == nil || mainScreen == nil || [screen isEqual:mainScreen]);
}

- (void)viewDidMoveToWindow
{
   [super viewDidMoveToWindow];
   [self updateIsMainScreen];
}

// Are we supposed to be drawing anything on this screen?
- (BOOL)isActiveScreen
{
   return !(mainScreenOnly && !isMainScreen);
}

- (void)startAnimation
{
   if (glview == nil) {
      LogError("startAnimation", "OS called startAnimation before NSOpenGLView initialized. This should not happen.");
      return;
   }
   [self updateIsMainScreen];
   if ([self isActiveScreen]) {
      // Allocate the texture storage object if necessary
      [[glview openGLContext] makeCurrentContext];
      if (matrixGlyphs == nil) {
         matrixGlyphs = [[MatrixTexture alloc] initWithNSOpenGLView:glview];
      }
      // Load and bind the texture bitmap
      if (![matrixGlyphs fileLoaded]) {
         // Load the PNG of glyphs
         [matrixGlyphs loadFromFile:@"Glyphs.png"];
      }
   }
   // Set up some parameters
   x = 0.0;
   y = 0.0;
   // Clear the screen to black, so that the screensaver fades to black
   [self drawGL];
   [super startAnimation];
}

// Free everything we allocated for the animation
- (void)releaseAnimationResources
{
   // Release the strips and the texture (which deletes the GL texture)
   matrixStrips = nil;
   matrixGlyphs = nil;
   saverParams.spawnChance = 0.2;
}

- (void)stopAnimation
{
   [super stopAnimation];
   [self releaseAnimationResources];
}

// The system is dismissing the screensaver. Stop the timer and free resources,
// as this instance may never be told to stop or be deallocated.
- (void)screenSaverWillStop:(NSNotification *)n
{
   if ([self isAnimating]) {
      [self stopAnimation];
   } else {
      [self releaseAnimationResources];
   }
}

// Our own drawing is all done by the OpenGL subview, which covers us completely
- (void)drawRect:(NSRect)rect
{
   [super drawRect:rect];
}

- (void)animateOneFrame
{
GLfloat xs,ys;
GLfloat d;
int cells;
MatrixStrip *strip;
MatrixStrip *newstrip;
int maxi;
int i;
struct MatrixStripParams tweaked;


   if (glview == nil) {
      LogError("animateOneFrame", "OS called animateOneFrame before NSOpenGLView initialized. This should not happen.");
      return;
   }
   
   // Anything to do?
   if (![self isActiveScreen]) {
      return;
   }

   if (matrixGlyphs == nil) {
      // Unfortunately the OS calling "draw frame" before "initialize screensaver" happens quite a lot,
       // and shouldn't be reported as an error
      return;
   }
   
   // Allocate the array of matrix strips if necessary
   if (matrixStrips == nil) {
      matrixStrips = [[NSMutableArray alloc] init];
   }
   // If the number of Matrix strips is less than the max, create another every now and again
   maxi = (int)[matrixStrips count];
   if ((maxi < saverParams.maxStrips) && (RANDOM_FLOAT_01 < saverParams.spawnChance)) {
      // Copy the current parameters
      tweaked = saverParams;
      // If the velocity is 0, we make the depth random
      if (saverParams.driftSpeed == 0.0) {
         d = -CLIP_NEAR - RANDOM_FLOAT_01 * (CLIP_FAR - CLIP_NEAR);
      } else {
         // Depth is whatever the current parameters are, only negative (away from the viewer)
         d = -saverParams.maxDepth;
      }
      // Work out range of X and Y at that depth
       ys = -d * TAN_FOV;
      xs = ys * aspectRatio;
       // Position the strip
      x = xs * RANDOM_FLOAT_11;
      y = saverParams.cellSize + ys * (saverParams.minStartY == 0.0 ? RANDOM_FLOAT_01 : saverParams.minStartY);
      // Work out how many cells it needs to cover the screen vertically
      cells = (int) ((y + ys) / saverParams.cellSize / QUAD_SQUISH_FACTOR) + 2;
      // Tweak the cursor speed a bit, randomly
       // (but never let it stop altogether, or the strip would never finish)
       tweaked.cursorSpeed = fmaxf(saverParams.cursorSpeed + 0.2 * RANDOM_FLOAT_01, 0.01);
       // I guess we could tweak the other parameters to vary things a bit, but it looks good enough anyway
      // Now create a strip
      newstrip = [[MatrixStrip alloc] initWithCells:cells x:x y:y z:d params:tweaked];
      if (newstrip == nil) {
         return;
      }
      // Add it to the array
       if (saverParams.driftSpeed == 0.0) {
          // In "zero velocity mode", we need to find the first strip that's in front of this one
          for (i = 0; i < maxi; i++) {
             strip = matrixStrips[i];
             if ([strip z] > d) {
                break;
             }
          }
          [matrixStrips insertObject:newstrip atIndex:i];
       } else {
          // In regular mode, strips are always added at the back
          if (maxi == 0) {
             // Adding first strip to array, so add it to the end
             [matrixStrips addObject:newstrip];
          } else {
             // Add it to the start of the array
             [matrixStrips insertObject:newstrip atIndex:0];
          }
       }
   }
   // Animate all the strips
   maxi = (int)[matrixStrips count];
   for (i = 0; i < maxi; i++) {
      strip = matrixStrips[i];
      if ([strip animateSelfIsComplete]) {
         // Strip has finished doing anything interesting, so delete it from the array
         // Note that the array releases it for us
         [matrixStrips removeObjectAtIndex:i];
         // The array is now one smaller, and we need to loop over the same index again
         i -= 1;
         maxi -= 1;
         // Plus we can now spawn new strips faster
         if (saverParams.spawnChance < 1.0) {
            saverParams.spawnChance += 0.05;
         }
      }
   }
   // Draw the new frame
   [self drawGL];
}

/// SECTION TWO
/// Everything OpenGL

// Initialize OpenGL
- (void)initGL
{
GLfloat fogcolor[4] = {0.0, 0.0, 0.0, 1.0};

   // Check there's an NSOpenGLView before we continue
   if (glview == nil) {
      LogError("initGL", "Screensaver called initGL before NSOpenGLView initialized. This should not happen.");
      return;
   }
   // OK, let's go (drawGL has made our context current)
   // All we need is flat shaded polygons
   glShadeModel(GL_FLAT);
   CheckGLError("initGL","glShadeModel(GL_FLAT)");
   // Enable textures, use them to modulate the brightness of the pixels of the quads we draw
   glTexEnvf(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_MODULATE);
   CheckGLError("initGL","glTexEnvf(GL_MODULATE)");
   glEnable(GL_TEXTURE_2D);
   CheckGLError("initGL","glEnable(GL_TEXTURE_2D)");
   // Skip stuff that's almost black
   glAlphaFunc(GL_GEQUAL, 0.0625);
   CheckGLError("initGL","glAlphaFunc(GL_GEQUAL, 0.0625)");
   // Set up the blending function for drawing the text quads
   glEnable(GL_BLEND);
   CheckGLError("initGL","glEnable(GL_BLEND)");
   glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
   CheckGLError("initGL","glBlendFunc");
   // Enable fog
   glEnable(GL_FOG);
   CheckGLError("initGL","glEnable(GL_FOG)");
   glFogi(GL_FOG_MODE, GL_LINEAR);
   CheckGLError("initGL","glFogi");
   glFogfv(GL_FOG_COLOR, fogcolor);
   CheckGLError("initGL","glFogf(GL_FOG_COLOR)");
   glFogf(GL_FOG_DENSITY, saverParams.fogDensity);
   CheckGLError("initGL","glFogf(GL_FOG_DENSITY)");
   glFogf(GL_FOG_START, CLIP_NEAR);
   CheckGLError("initGL","glFogf(GL_FOG_START)");
   glFogf(GL_FOG_END, CLIP_FAR*1.2);
   CheckGLError("initGL","glFogf(GL_FOG_END)");
   // Now maybe disable fog...
   if (saverParams.fogDensity == 0.0) {
      glDisable(GL_FOG);
      CheckGLError("initGL","glDisable(GL_FOG)");
   } else {
      glEnable(GL_FOG);
      CheckGLError("initGL","glEnable(GL_FOG)");
   }
   // We use GL arrays for drawing the Matrix strips, so enable them now
   glEnableClientState(GL_VERTEX_ARRAY);
   CheckGLError("initGL","glEnableClientState(GL_VERTEX_ARRAY)");
   glEnableClientState(GL_COLOR_ARRAY);
   CheckGLError("initGL","glEnableClientState(GL_COLOR_ARRAY)");
   glEnableClientState(GL_TEXTURE_COORD_ARRAY);
   CheckGLError("initGL","glEnableClientState(GL_TEXTURE_COORD_ARRAY)");   
}

// Set up viewport and projection appropriately for the given screen rectangle
- (void)resizeGL:(int)width :(int) height
{
   if (glview == nil) {
      LogError("resizeGL", "Screensaver called resizeGL before NSOpenGLView initialized. This should not happen.");
      return;
   }
   if (width <= 0 || height <= 0) {
      // Not on screen yet; avoid dividing by zero below
      return;
   }
   [[glview openGLContext] makeCurrentContext];
   glViewport(0, 0, width, height);
   CheckGLError("resizeGL","glViewport");
   glMatrixMode(GL_PROJECTION);
   CheckGLError("resizeGL","glMatrixMode(GL_PROJECTION)");
   glLoadIdentity();
   CheckGLError("resizeGL","glLoadIdentity");
   // 45 degrees FOV = 50mm lens on a 35mm camera, should look natural
   // Store the aspect ratio for later use
   aspectRatio = (GLfloat) width / (GLfloat) height;
   saverParams.aspectRatio = aspectRatio;
   gluPerspective(FIELD_OF_VIEW, aspectRatio, CLIP_NEAR, CLIP_FAR);
   CheckGLError("resizeGL","gluPerspective(FIELD_OF_VIEW)");
   // Go back to manipulating the model (objects)
   glMatrixMode(GL_MODELVIEW);
   CheckGLError("resizeGL","glMatrixMode(GL_MODELVIEW)");
   glLoadIdentity();
   CheckGLError("resizeGL","glLoadIdentity");
}

- (void)drawGL
{
GLuint tex;
NSOpenGLContext *context;

   if (glview == nil) {
      LogError("drawGL", "Screensaver called drawGL called before NSOpenGLView initialized. This should not happen.");
      return;
   }
   context = [glview openGLContext];
   [context makeCurrentContext];
   // Initialize OpenGL if necessary
   if (!didGLinit) {
      didGLinit = TRUE;
      [self initGL];
   }
   // Switch fog on or off, as the preferences may have changed
   if (saverParams.fogDensity == 0.0) {
      glDisable(GL_FOG);
   } else {
      glEnable(GL_FOG);
   }
   CheckGLError("drawGL","glEnable/glDisable(GL_FOG)");
   glClearColor(0.0, 0.0, 0.0, 1.0);
   CheckGLError("drawGL","glClearColor(0.0, 0.0, 0.0, 1.0)");
   glClear(GL_COLOR_BUFFER_BIT);
   CheckGLError("drawGL","glClear(GL_COLOR_BUFFER_BIT)");
   // Unfortunately the OS calling "draw frame" before "initialize screensaver" happens quite a lot,
   // so if there's nothing to draw yet, we just show black
   if ([self isActiveScreen] && [matrixGlyphs fileLoaded] && matrixStrips != nil) {
      // Bind the texture we loaded
      tex = [matrixGlyphs GLtexture];
      glBindTexture(GL_TEXTURE_2D, tex);
      CheckGLError("drawGL","glBindTexture");
      // Draw all the strips by asking them to draw themselves
      for (MatrixStrip *strip in matrixStrips) {
         [strip drawSelf];
      }
   }
   // Show what we drew
   [context flushBuffer];
}

/// SECTION THREE
/// Configuration sheet handling

- (BOOL)hasConfigureSheet
{
   return YES;
}

- (NSWindow*)configureSheet
{
   if (!prefsWindow) {
      prefsWindow = [[MatrixPrefsWindow alloc]
      initWithWindowNibName:@"Matrix"];
   }
   [prefsWindow loadSettings];
   return [prefsWindow window];
}

/// SECTION FOUR
/// Clean up after ourselves
- (void) dealloc
{
   [[NSNotificationCenter defaultCenter] removeObserver:self];
   [[NSDistributedNotificationCenter defaultCenter] removeObserver:self];
   [glview setRenderer:nil];
}
@end
