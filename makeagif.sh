#!/bin/bash
#set -v -x	
set -e
Lenght=3
fps=15
compression=30
width=600
height=500
maxcompression=100
maxsize=5099999
overwrite="True"
random="False"
seek="0"
cropping="False"
regextime='^[0-9]+($|\.[0-9]+$)|(^[0-9]+(:[0-6]?[0-9]){2}|^[0-6]?[0-9]:?[0-6]?[0-9]?)($|\.[0-9]+$)'
type=gif
exiterror ()
{
>&2 echo -e "Usage is: "$(basename $0)" [-s -f-l -w -m -r -o -c ] \e[3mpicture\e[0m|\e[3mlink\e[0m"
exit 1
}
if [ "$#" -lt 1 ]; then
	exiterror
fi
Video="${@: -1}"
ScVideo="$Video"

test=$(ffprobe -v quiet -show_format "$Video" | grep "duration" | tail -1)
if [ "$test" == "duration=N/A" ]
	then
	>&2 echo "$Video is not a Video"
	exit 1
fi



while getopts 's:f:l:m:w:C:t:T:orc' flag; do
case "${flag}" in
	s) if [[ ! "${OPTARG}" =~ $regextime ]]; then
		>&2 echo "Does not look be a valid timecode: $OPTARG"
		exit 1
	  fi
	  seek="${OPTARG}" 
	;;
	f) fps="${OPTARG}" ;;
	l) if [[ ! "${OPTARG}" =~ $regextime ]]; then
		>&2 echo "Does not look be a valid timecode: $OPTARG"
		exit 1
	  fi
	  Lenght="${OPTARG}" ;;
	w) width="${OPTARG}"; choice="width" ;;
	m) maxsize=$(echo "$OPTARG*1000000" | bc -s)
	maxsize="${maxsize%%.*}"
	;;
	r) random="True" ;;
	o) if [ -d "${OPTARG}" ]; then if [ ! ${OPTARG: -1} == "/" ]; then output="${OPTARG}""/"; else output="${OPTARG}"; fi; fi 
	;;
	C) cropvalue="crop=${OPTARG}," ;;
	c) cropping="True" ;;
	t) text="$OPTARG" ;;
	T) type="$OPTARG" ;;
	*) error "Unexpected option ${flag}"
	exiterror ;;
esac
done


Name=$(basename "$Video")
output="$output$Name.gif"

if [ $overwrite == "False" ]; then
	if [ -f "$output" ]; then
		>&2 echo "File found, not overwriting"
		exit 1
	fi
fi

if [ $random == "True" ]; then
	lenghtofv=$(mediainfo --Inform="General;%Duration%" "$Video")
	lenghtofv=$((lenghtofv/1000))
	lenghtofv=$((lenghtofv-Lenght))
	seek=$(shuf -i 1-$lenghtofv -n 1)
fi


testsizes () 
{
testfps=$(ffprobe -v 0 -of csv=p=0 -select_streams v:0 -show_entries stream=r_frame_rate "$Video")
testfps=$((testfps))
if ! [ "$testfps" == "" ]; then
	if [ "$fps" -gt "$testfps" ]; then
		>&2 echo "The videos FPS is lower than choosen. Changing FPS to $testfps"
		fps="$testfps"
	fi
fi
testwidth=$(mediainfo --inform="Video;%Width%" "$Video")
if ! [ "$testwidth" == "" ]; then
	if [ "$testwidth" -lt "$width" ]; then
		>&2 echo "The videos Width is lower than choosen. Changing width to $testwidth"
			width=$testwidth
	fi
fi
}

checkscale ()
{
vwidth=$(ffprobe -v quiet -print_format json -show_format -show_streams "$ScVideo" | jq -r '.streams[0].width // .streams[1].width')
vheight=$(ffprobe -v quiet -print_format json -show_format -show_streams "$ScVideo" | jq -r '.streams[0].height // .streams[1].height')

if [ $vheight -gt $vwidth ]; then
	if [ "$vheight" -lt "$height" ]; then
		>&2 echo "The videos height is lower than choosen. Changing width to $vheight"
		height=$vheight
	fi
	scalesize="scale=-1:$height"
	else
	if [ "$vwidth" -lt "$width" ]; then
		>&2 echo "The videos Width is lower than choosen. Changing width to $vwidth"
		width=$vwidth
	fi
	scalesize="scale=$width:-1"
fi
}
makegif ()
{
if [ "$type" = webp ]; then
if [ -z "$text" ]; then
	ffmpeg -y -hide_banner -loglevel quiet  -ss "$seek" -t "$Lenght" -i "$Video" -filter_complex "$cropvalue""fps="$fps",$scalesize" -q:v 95 -loop 0 "$output.webp"
else
	ffmpeg -y -hide_banner -loglevel quiet -ss "$seek" -t "$Lenght" -i "$Video" -filter_complex "$cropvalue""fps="$fps",$scalesize, \
	drawtext=fontfile=FreeSans.ttf:fontcolor=white:text=$text:fontsize=48:x=(w-text_w)/2: y=(h-text_h)/1.10: fix_bounds=1: bordercolor=black: borderw=2" -q:v 95 -loop 0 "$output.webp"
fi
else
if [ -z "$text" ]; then
	ffmpeg -y -hide_banner -loglevel quiet  -ss "$seek" -t "$Lenght" -i "$Video" -filter_complex "$cropvalue""fps="$fps",$scalesize:flags=lanczos,split[s0][s1];[s0]palettegen=stats_mode=diff[p];[s1]fifo[buff1];[buff1][p]paletteuse" "$output"
else
	ffmpeg -y -hide_banner -loglevel quiet -ss "$seek" -t "$Lenght" -i "$Video" -filter_complex "$cropvalue""fps="$fps",$scalesize:flags=lanczos,split[s0][s1];[s0]palettegen=stats_mode=diff[p];[s1]fifo[buff1];[buff1][p]paletteuse, \
	drawtext=fontfile=FreeSans.ttf:fontcolor=white:text=$text:fontsize=48:x=(w-text_w)/2: y=(h-text_h)/1.10: fix_bounds=1: bordercolor=black: borderw=2" "$output"
fi

#ffmpeg -y -ss "$seek" -t "$Lenght" -i "$Video" -lossless 0 -filter_complex "fps="$fps",$scalesize "$output"
fi
}

reducesize1 ()
{
size=$(stat -c%s "$output")
doublesize=$((maxsize*2))
if [ "$size" -gt $doublesize ]; then
	compression=50
	if [ ! "$choice" = "width" ]; then width=$((width - 50)); fi
	fps=$((fps -1))
	>&2 echo "Width is now $width and fps is now $fps"
	rm "$output"
	checkscale
	makegif
	reducesize1
fi
}

reducesize2 ()
{
size=$(stat -c%s "$output")
if [ "$size" -gt $maxsize ]; then
	gifsicle -b --lossy="$compression" -o "$output" "$output"
	>&2 echo "Compressing at $compression"
	compression=$((compression + 20))
	if [ $compression -gt $maxcompression ]; then
		compression=50
		if [ ! "$choice" = "width" ]; then width=$((width - 50)); fi
		fps=$((fps -1))
		>&2 echo "Width is now $width and fps is now $fps"
		rm "$output"
		checkscale
		makegif
	fi
	reducesize2
fi
}

if [ $cropping == "True" ]&&[ -z $cropvalue ]; then
cropvalue=$(ffmpeg -i "$Video" -t 1 -vf cropdetect -f null - 2>&1 | awk '/crop/ { print $NF }' | tail -1)
ffmpeg -y -hide_banner -loglevel quiet -ss "$seek" -i "$Video" -vframes 1 -vf "$cropvalue" "$output".still.png
cropvalue="$cropvalue,"
ScVideo="$output".still.png
fi

testsizes
checkscale
>&2 echo "Doing $Name, starting with: $fps fps and width: $width starting at $seek, and a max size of $maxsize"
makegif
reducesize1
>&2 echo "Compressing at $compression"
gifsicle -b --lossy="$compression" -o "$output" "$output"
compression=$((compression + 20))
reducesize2
if [ $cropping == "True" ]&&[ -f "$output".still.png ]; then
	rm "$output".still.png
fi
finalsize=$(du -h "$output" | awk '{print $1}')
>&2 echo "Done. File size is $finalsize."
echo "$output"
exit 0