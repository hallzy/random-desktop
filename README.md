# Random Desktop

This script will run and see if there are any new images from a select few
subreddits. If there is a new image that is close to a 16:9 aspect ratio then it
will download it and set it as the desktop background.

Otherwise, it will set the background to a random image in the
`desktop_backgrounds` folder.

The `downloaded_background_images.txt` file keeps track of reddit URLs that this
script has checked so that it doesn't download the same image again.
