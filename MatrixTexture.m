// This file is part of Red Pill
// A 3D OpenGL "Matrix" screensaver for Mac OS X
// Copyright (C) 2002-2005 mathew <meta@pobox.com>
// Modified 2026 by Andreas Plagens for modern macOS <https://github.com/andiqq/RedPill>
//
// Red Pill is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.   See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program; if not, write to the Free Software
// Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
// or visit <URL:http://www.fsf.org/>

#import "MatrixTexture.h"

@implementation MatrixTexture

// Initializer needs to know what GL view the texture will be used in.
- (instancetype)initWithNSOpenGLView:(NSOpenGLView *)someview
{
   if (someview == nil) {
      LogError("initWithNSOpenGLView", "initWithNSOpenGLView was passed a nil NSOpenGLView. This should not happen.");
   }
   if (self = [super init]) {
      glview = someview;
      fileWasLoaded = FALSE;
   }
   return self;
}

- (void) dealloc
{
   // Unload the OpenGL texture
   if (texture != 0) {
      [[glview openGLContext] makeCurrentContext];
      glDeleteTextures(1, &texture);
      CheckGLError("dealloc","glDeleteTextures");
   }
}

- (GLuint) GLtexture
{
   return texture;
}

- (BOOL) fileLoaded
{
   return fileWasLoaded;
}

// Load bitmap data from a file, then create an OpenGL texture from it.
- (BOOL)loadFromFile:(NSString *)filename
{
   // Find the image file inside our own bundle (not the host application's)
   NSURL *url = [[NSBundle bundleForClass:[self class]] URLForResource:filename withExtension:nil];
   if (url == nil) {
      LogError("loadFromFile", "Glyph image is missing from the bundle.");
      return FALSE;
   }
   CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
   if (source == NULL) {
      LogError("loadFromFile", "Could not open glyph image.");
      return FALSE;
   }
   CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, NULL);
   CFRelease(source);
   if (image == NULL) {
      LogError("loadFromFile", "Could not decode glyph image. Image file is broken?");
      return FALSE;
   }

   // Redraw the image into a buffer whose layout we control (tightly packed RGBA),
   // whatever format the file happens to be stored in (palette, gray, RGB...)
   size_t width = CGImageGetWidth(image);
   size_t height = CGImageGetHeight(image);
   size_t rowsize = width * 4;
   if (width == 0 || height == 0 || width > 4096 || height > 4096) {
      LogError("loadFromFile", "Glyph image has unexpected dimensions.");
      CGImageRelease(image);
      return FALSE;
   }
   NSMutableData *pixels = [NSMutableData dataWithLength:rowsize * height];
   // Draw in the image's own color space, so the pixel values aren't color-corrected
   CGColorSpaceRef rgb = CGImageGetColorSpace(image);
   if (rgb != NULL && CGColorSpaceGetModel(rgb) == kCGColorSpaceModelIndexed) {
      rgb = CGColorSpaceGetBaseColorSpace(rgb);
   }
   if (rgb != NULL && CGColorSpaceGetModel(rgb) == kCGColorSpaceModelRGB) {
      CGColorSpaceRetain(rgb);
   } else {
      rgb = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
   }
   CGContextRef ctx = CGBitmapContextCreate([pixels mutableBytes], width, height, 8, rowsize, rgb,
                                            (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
   CGColorSpaceRelease(rgb);
   if (ctx == NULL) {
      LogError("loadFromFile", "failed to allocate space for the bitmap.");
      CGImageRelease(image);
      return FALSE;
   }
   // Flip vertically, so the first row in memory is the bottom of the image, as OpenGL expects
   CGContextTranslateCTM(ctx, 0, (CGFloat)height);
   CGContextScaleCTM(ctx, 1.0, -1.0);
   CGContextDrawImage(ctx, CGRectMake(0, 0, (CGFloat)width, (CGFloat)height), image);
   CGContextRelease(ctx);
   CGImageRelease(image);

   // Now create an OpenGL texture
   [[glview openGLContext] makeCurrentContext];
   if (texture == 0) {
      // Find free texture slot
      glGenTextures(1, &texture);
      CheckGLError("loadFromFile","glGenTextures");
   }
   glBindTexture(GL_TEXTURE_2D, texture);
   CheckGLError("loadFromFile","glBindTexture");
   glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
   CheckGLError("loadFromFile","glTexParameteri");
   glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
   CheckGLError("loadFromFile","glTexParameteri");
   glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
   CheckGLError("loadFromFile","glPixelStorei");
   // Define the texture from the bitmap data
   // We want an INTENSITY texture where alpha = intensity of pixel
   // as we're modulating quads into letters of whatever color
   // and the source image is colored letters on black
   glTexImage2D(GL_TEXTURE_2D, 0, GL_INTENSITY, (GLsizei) width, (GLsizei) height, 0, GL_RGBA, GL_UNSIGNED_BYTE, [pixels bytes]);
   CheckGLError("loadFromFile","glTexImage2D");
   fileWasLoaded = TRUE;
   return TRUE;
}

@end
