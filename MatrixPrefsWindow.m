// This file is part of Red Pill
// A 3D OpenGL "Matrix" screensaver for Mac OS X
// Copyright (C) 2002, 2003 mathew <meta@pobox.com>
// Modified 2026 by Andreas Plagens for modern macOS <https://github.com/andiqq/RedPill>
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
// Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
// or visit <URL:http://www.fsf.org/>

#import "MatrixPrefsWindow.h"

@implementation MatrixPrefsWindow

- (void)loadSettings
{
   // Make sure the nib has been loaded, so the outlets are connected
   [self window];
   // Work out what our defaults are called
   NSString *identifier = [[NSBundle bundleForClass:[self class]] bundleIdentifier];
   if(identifier == nil) {
      LogError("loadSettings", "Trying to load preferences but identifier is nil.");
      return;
   }
   // Load defaults
   ScreenSaverDefaults *defaults = [ScreenSaverDefaults defaultsForModuleWithName:identifier];
   // Initialize the UI elements
   [strips setFloatValue:[defaults floatForKey:STRIPS_KEY]];
   [velocity setFloatValue:[defaults floatForKey:VELOCITY_KEY]];
   [depth setFloatValue:[defaults floatForKey:DEPTH_KEY]];
   [cycling setFloatValue:[defaults floatForKey:CYCLING_KEY]];
   [falling setFloatValue:[defaults floatForKey:FALLING_KEY]];
   [cursor setFloatValue:[defaults floatForKey:CURSOR_KEY]];
   [fog setFloatValue:[defaults floatForKey:FOG_KEY]];
   [topstart setState:([defaults boolForKey:TOPSTART_KEY] ? NSControlStateValueOn : NSControlStateValueOff)];
   [mainonly setState:([defaults boolForKey:MAINONLY_KEY] ? NSControlStateValueOn : NSControlStateValueOff)];
   // Find out version from bundle
   NSBundle *bundle = [NSBundle bundleForClass:[self class]];
   NSString *versionString = [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
   [version setStringValue:(versionString ?: @"")];
   [spoon setState:NSControlStateValueOff];
   // Hide spoon mode most of the time
   if (arc4random_uniform(5) != 3) {
      [spoon setTransparent:TRUE];
   } else {
      [spoon setTransparent:FALSE];
   }
}

// Dismiss the configuration sheet.
// Modern macOS hosts the sheet on a parent window, and ignores [NSApp endSheet:].
- (void)closeSheet
{
   NSWindow *sheet = [self window];
   NSWindow *parent = [sheet sheetParent];
   if (parent != nil) {
      [parent endSheet:sheet];
   } else {
      [NSApp endSheet:sheet];
      [sheet orderOut:self];
   }
}

// Reset the values of the sliders to their defaults
- (IBAction)reset:(id)sender
{
   [strips setFloatValue:[STRIPS_DEFAULT floatValue]];
   [velocity setFloatValue:[VELOCITY_DEFAULT floatValue]];
   [depth setFloatValue:[DEPTH_DEFAULT floatValue]];
   [cycling setFloatValue:[CYCLING_DEFAULT floatValue]];
   [falling setFloatValue:[FALLING_DEFAULT floatValue]];
   [cursor setFloatValue:[CURSOR_DEFAULT floatValue]];
   [fog setFloatValue:[FOG_DEFAULT floatValue]];
   [topstart setState:(TOPSTART_DEFAULT_BOOLEAN ? NSControlStateValueOn : NSControlStateValueOff)];
   [mainonly setState:(MAINONLY_DEFAULT_BOOLEAN ? NSControlStateValueOn : NSControlStateValueOff)];
}

// The About button takes them to a web site
- (IBAction)about:(id)sender
{
   NSURL *url = [NSURL URLWithString:ABOUT_URL];
   if (url != nil) {
      [[NSWorkspace sharedWorkspace] openURL:url];
   }
}

- (IBAction)cancel:(id)sender
{
   [self closeSheet];
}

- (IBAction)spoonclick:(id)sender
{
   [spoon setTransparent:FALSE];
}
   
- (IBAction)ok:(id)sender
{
   // Work out what our defaults are called
   NSString *identifier = [[NSBundle bundleForClass:[self class]] bundleIdentifier];
   if(identifier == nil) {
      LogError("ok", "Trying to save preferences but identifier is nil.");
      [self closeSheet];
      return;
   }
   // Load defaults
   ScreenSaverDefaults *defaults = [ScreenSaverDefaults defaultsForModuleWithName:identifier];
   // Set values based on new positions and states of UI elements
   [defaults setFloat:[strips floatValue] forKey:STRIPS_KEY];
   [defaults setFloat:[velocity floatValue] forKey:VELOCITY_KEY];
   [defaults setFloat:[depth floatValue] forKey:DEPTH_KEY];
   [defaults setFloat:[cycling floatValue] forKey:CYCLING_KEY];
   [defaults setFloat:[falling floatValue] forKey:FALLING_KEY];
   [defaults setFloat:[cursor floatValue] forKey:CURSOR_KEY];
   [defaults setFloat:[fog floatValue] forKey:FOG_KEY];
   [defaults setBool:([topstart state] == NSControlStateValueOn) forKey:TOPSTART_KEY];
   [defaults setBool:([mainonly state] == NSControlStateValueOn) forKey:MAINONLY_KEY];
   // Plug web site if user selects spoon mode
   if ([spoon state] == NSControlStateValueOn) {
      NSAlert *alert = [[NSAlert alloc] init];
      alert.messageText = @"Realize";
      alert.informativeText = @"There is no spoon.";
      [alert addButtonWithTitle:@"OK"];
      [alert runModal];
      [self about:sender];
   }
   // Update to disk
   [defaults synchronize];

   // Tell the main scrensaver loop to reload the preferences from us
   [[NSNotificationCenter defaultCenter] postNotificationName:PREFS_NOTIFICATION object:nil];

   [self closeSheet];
}
@end
