#!/bin/bash

SCRIPTPATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"

getLocalImg() {
    keepImg="n"
    while [ "$keepImg" = "n" ] || [ "$keepImg" = "N" ]; do
        # No new images on reddit. Fallback to a saved image on disk.

        localimg="$(env ls "$SCRIPTPATH/desktop_backgrounds/" | shuf -n 1)"

        feh --bg-max "$SCRIPTPATH/desktop_backgrounds/${localimg}"

        notify-send -t 0 'Background Image Updated' "From local drive: $localimg"

        if [ "$isCron" -eq 1 ]; then
            exit 0;
        fi

        read -r -p "Do you want to keep this image? (Y/n) " keepImg
    done
}

# Create cronjob that runs every hour on the hour:
# 0 *   *   *   * DISPLAY=:0 /path/to/random-image.sh cron > /dev/null 2>&1

isCron=0
if [ "$1" = "cron" ]; then
    isCron=1;
fi

if [ "$1" = "local" ]; then
    getLocalImg
    exit 0
fi

# Retrieve photos from these subreddits
SUBREDDITS='
{
    "data": [
        "spaceflightporn",
        "spaceporn",
        "astrophotography",
        "ImagesOfSpace",
        "rocketporn",
        "VancouverPhotos",
        "EarthPorn",
        "winterporn"
    ]
}'

SKIPPED=''

DEBUG="/tmp/random-image-debug.log"
true > "$DEBUG"

# Place to save the JSON for a subreddit
REDDIT="$SCRIPTPATH/reddit.json"

# Get the number of subreddits listed above (parse the array, and subtract 2
# from the number of lines because the output produces 2 extra lines)
NUM_SUBS="$(echo "$SUBREDDITS" | jq -r '.data' | wc -l)"
NUM_SUBS="$((NUM_SUBS-2))"

# Pick a random subreddit
SUB_IDX="$((RANDOM%NUM_SUBS))"

# Iterate through the subreddits if needed
SUB_ITERATION=0
while [ "$SUB_ITERATION" -lt "$NUM_SUBS" ]; do
    SUB_ITERATION=$((SUB_ITERATION+1))

    # Go to the next subreddit... If we are past the end, then start back at 0
    SUB_IDX=$((SUB_IDX+1))
    if [ "$SUB_IDX" -ge "$NUM_SUBS" ]; then
        SUB_IDX=0
    fi

    # Get the name of the subreddit that was chosen
    SUB="$(echo "$SUBREDDITS" | jq -r ".data[$SUB_IDX]")"

    echo "Checking Subreddit - '$SUB'" | tee -a "$DEBUG"

    # Download the JSON for the chosen subreddit
    wget -q -O "$REDDIT" "https://www.reddit.com/r/${SUB}/new.json?limit=100"
    if [ "$?" -ne 0 ]; then
        SKIPPED="$SKIPPED\nSKIPPING SUBREDDIT '$SUB'. Error occurred while downloading json";
        continue;
    fi

    # Find out how many posts we downloaded in the JSON... I think this is
    # always 25? Not sure how to change that...
    NUM_POSTS="$(jq -r '.data.dist' "$REDDIT")"

    echo "Number of Posts: $NUM_POSTS" | tee -a "$DEBUG"

    # Randomly choose a post
    IDX="$((RANDOM%NUM_POSTS))"

    # Iterate through all posts until we find one that will work
    ITERATION=0
    while [ "$ITERATION" -lt "$NUM_POSTS" ]; do
        ITERATION="$((ITERATION+1))"

        # Try the next post. Start back at the 0 if we go too far
        IDX="$((IDX+1))"
        if [ "$IDX" -ge "$NUM_POSTS" ]; then
            IDX=0
        fi

        echo "Checking Post #${IDX}" | tee -a "$DEBUG";

        # Get information about the post
        HAS_PREVIEW=".data.children[$IDX].data.preview.enabled"
        URL=".data.children[$IDX].data.permalink"
        IS_VIDEO=".data.children[$IDX].data.is_video"
        WIDTH=".data.children[$IDX].data.preview.images[0].source.width"
        HEIGHT=".data.children[$IDX].data.preview.images[0].source.height"
        TITLE=".data.children[$IDX].data.title"
        IMG_URL=".data.children[$IDX].data.url"

        # Wow jq is slow. Run it once for all the queries at once so I don't
        # have to run it multiple times. This increases speed significantly
        DATA="$(jq -r "$HAS_PREVIEW,$URL,$IS_VIDEO,$WIDTH,$HEIGHT,$TITLE,$IMG_URL" "$REDDIT")"

        HAS_PREVIEW="$(echo "$DATA" | awk 'NR == 1')"
        URL="https://reddit.com$(echo "$DATA" | awk 'NR == 2')"
        IS_VIDEO="$(echo "$DATA" | awk 'NR == 3')"
        WIDTH="$(echo "$DATA" | awk 'NR == 4')"
        HEIGHT="$(echo "$DATA" | awk 'NR == 5')"
        TITLE="$(echo "$DATA" | awk 'NR == 6')"
        IMG_URL="$(echo "$DATA" | awk 'NR == 7')"

        echo "has preview: $HAS_PREVIEW"
        echo "url:         $URL"
        echo "is video:    $IS_VIDEO"
        echo "width:       $WIDTH"
        echo "height:      $HEIGHT"
        echo "title:       $TITLE"
        echo "img url:     $IMG_URL"

        # If the post doesn't have a preview, then it doesn't seem to be a
        # photo, so skip it.
        if [ "$HAS_PREVIEW" != 'true' ]; then
            echo "No Preview, probably not an image - $URL" | tee -a "$DEBUG"
            continue;
        fi

        # If it is a video, also skip
        if [ "$IS_VIDEO" = 'true' ]; then
            echo "IS VIDEO: $URL" | tee -a "$DEBUG"
            continue;
        fi

        # Is This image the one that is currently being used?
        if grep -qF "$URL" "$SCRIPTPATH/downloaded_background_images.txt"; then
            echo "This image has been used before, so skipping..." | tee -a "$DEBUG"
            continue;
        fi

        # Ideally, a desktop background would have a width to height ratio of 16:9
        # But I will allow for some wiggle room (16:9 is a about 1.78:1)
        RATIO="$(echo "$WIDTH / $HEIGHT" | bc -l)"
        if (( $(echo "$RATIO > 2.1 || $RATIO < 1.6" | bc -l) )); then
            echo "Skipping because dimensions are not ideal - $URL" | tee -a "$DEBUG"
            continue;
        fi

        # Add info about the image to a text file so I can find it later if
        # needed
        echo "$TITLE - $URL - $IMG_URL" >> "$SCRIPTPATH/downloaded_background_images.txt"

        # Set the image as my desktop background
        feh --bg-max "$IMG_URL"

        # Tell me about the change and what the photo title is
        notify-send -t 0 'Background Image Updated' "From 'r/$SUB': $TITLE"

        if [ "$isCron" -eq 1 ]; then
            exit 0;
        fi

        read -r -p "Do you want to keep this image? (Y/n) " choice
        if [ "$choice" = 'n' ] || [ "$choice" = 'N' ]; then
            continue;
        fi

        filename="$(basename -- "$IMG_URL")"
        extension="${filename##*.}"

        wget -O "desktop_backgrounds/${TITLE}.${extension}" "$IMG_URL"

        printf "$SKIPPED\n"
        exit 0;
    done
done

getLocalImg
printf "$SKIPPED\n"
