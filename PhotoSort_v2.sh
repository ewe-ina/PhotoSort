#!/bin/bash

#Autor: Ewelina Walkusz-Minko, ewelina.walkusz@protonmail.com
#Duży skrypt (wykorzystuje m.in.: zenity, exiftool, jq)
#PhotoSort - organizer zdjęć. Czerwiec 2021. Wersja 2.0
#Skrypt wyszukuje w zadanym miejscu pliki graficzne, sortuje do odpowiednich katalogów w miejscu docelowym
#oraz zmienia nazwy, bazując na dacie i czasie wykonania zdjęcia, przy wykorzystaniu danych EXIF.
############################

#funkcja wyciszająca ostrzeżenia zenity, uwaga, może czasem powodować problemy
zenity(){
	/usr/bin/zenity "$@" 2>/dev/null
}
. PhotoSortConfig.rc
TOOLS=(zenity exiftool jq)
DESTINATION_PATTERN="%Y%m%d"				#format nazwy katalogu docelowego
DATE_FORMAT="%Y:%m:%d"						#fotmat daty dla sed
OUTPUT_DATE_FORMAT="%Y%m%d_%H%M%S"
TEXT_FILE=`dirname $0`/TEXT					#plik "TEXT" musi znajdować się w tym samym katalogu co ten skrypt

#Sprawdzenie, czy wymagane narzędzia są zainstalowane
for TOOL in ${TOOLS[*]}
do
	type $TOOL >/dev/null 2>&1 || { echo >&2 "Skrypt do prawidłowego działania wymaga $TOOL. Zainstaluj $TOOL i spróbuj ponownie."
	exit 1 
	}
done

if [ $# -eq 0 ]		#jeśli bez parametrów
then

	#Komunikat powitalny
	zenity 	--text-info \
			--title="Organizer zdjęć" \
			--filename=$TEXT_FILE \
			--width 600 --height 260
	case $? in
		0)
			echo "Kontynuujemy."
			;;
		1)
			echo "Kończymy działanie skryptu."
			exit 
			;;
		-1)
			echo "Nieoczekiwany błąd."
			exit 1
			;;
	esac

	#Obsługa spacji w nazwach plików
	SAVEIFS=$IFS
	IFS=$(echo -en "\n\b")

	#Katalog źródłowy
	echo -e "\nWybierz katalog źródłowy."
	SOURCE=$(zenity	--file-selection --directory \
					--title="Wybierz katalog źródłowy" \
					--width 1000 --height 500)
	#echo -e "Wybrany katalog źródłowy: $SOURCE\n"
	case $? in
		0)
			echo -e "Wybrany katalog źródłowy: $SOURCE\n"
			;;
		1)
			SOURCE=$SOURCE_DEFOULT
			echo -e "Domyślny katalog źródłowy: $SOURCE\n"
			;;
		-1)
			echo "Nieoczekiwany błąd."
			exit 1
			;;
	esac

	#Katalog docelowy
	echo -e "Wybierz katalog docelowy."
	DESTINATION=$(zenity 	--file-selection --directory \
							--title="Wybierz katalog docelowy" \
							--width 1000 --height 500)
	#echo -e "\nWybrany katalog docelowy: $DESTINATION\n"
	case $? in
		0)
			echo -e "Wybrany katalog docelowy: $DESTINATION\n"
			;;
		1)
			DESTINATION=$DESTINATION_DEFOULT
			echo -e "Domyślny katalog docelowy: $DESTINATION\n"
			;;
		-1)
			echo "Nieoczekiwany błąd."
			exit 1
			;;
	esac

	#Potwierdzenie wyboru katalogów
	if zenity	--question \
				--ok-label="OK" \
				--cancel-label="Cancel" \
				--title="Potwierdź wybór" \
				--text '<span foreground="blue" font="12"><i>Katalog źródłowy:\t</i><b>'$SOURCE'</b>\n\n<i>Katalog docelowy: \t</i><b>'$DESTINATION'</b></span>' \
				--width 500 --height 50
	then
		echo -e "Wybór katalogów potwierdzony.\n"
	else
		exit 1
	fi

	#Wybór zadania: kopiowanie/przenoszenie plików
	TASK=$(zenity 	--list \
					--title="Przenieś/kopiuj" \
					--text "Czy chcesz przenieść, czy skopiować pliki?" \
					--radiolist \
					--column "Wybierz" \
					--column "Zadanie" TRUE Kopiuj FALSE Przenieś)
	echo -e "Wybrane zadanie: $TASK\n"

else
	#getopts
	SOURCE=$SOURCE_DEFOULT
	DESTINATION=$DESTINATION_DEFOULT
	TASK=$TASK_DEFOULT

	version()
	{
		echo "PhotoSort - organizer zdjęć. Czerwiec 2021. Wersja 2.0"
		echo "Licencja: Niniejszy skrypt udostępniam na licencji GPL 3.0"
		echo "Autor: Ewelina Walkusz-Minko, ewelina.walkusz@protonmail.com"
		exit
	}

	usage()		#funkcja: wydruk sposobów użycia wywołania
	{
		echo "Wywołanie - kopiuj:	$0 [-s SOURCE_PATH] [-d DESTINATION_PATH] [-c]"
		echo "Wywołanie - przenieś:	$0 [-s SOURCE_PATH] [-d DESTINATION_PATH] [-m]"
		echo "Wywołanie: 		$0 [-h] wyświetli pełną pomoc"
	}

	help()		#funkcja: pomoc
	{
		echo "Skrypt PhotoSort służy do sortowania zdjęć."
		echo "Można z niego korzystać na dwa sposoby:"
		echo "Wywołanie bez parametrów: $0 uruchomi pełny tryb okienkowy."
		echo "Wywołanie z parametrami:"
		usage
		exit
	}

	while getopts ":s:d:cmhv" OPTION; do
		case $OPTION in
			s)
				SOURCE="$OPTARG"
				;;
			d)
				DESTINATION="$OPTARG"
				;;
			c)
				TASK="Kopiuj"
				;;
			m)
				TASK="Przenieś"
				;;
			h)
				help
				;;
			v)
				version
				;;
			?)
				usage
				exit 1
				;;
		esac
	done
	echo "Katalog źródłowy: $SOURCE"
	echo "Katalog docelowy: $DESTINATION"
	echo -e "Zadanie: $TASK\n"
	sleep 2
	echo -e "Zaczynamy...\n"
fi

for FILE in $(find "$SOURCE" -iname "*.JPEG" -or -iname "*.JPG" -or -iname "*.GIF" -or -iname "*.PNG" -or -iname "*.RAW" -type f)
do
	INPUT_FILE=${FILE}
	INPUT_FILE_NAME=$(echo ${FILE##*/})
	INPUT_FILE_EXTENSION=$(echo ${FILE##*.})
	DATE=$(exiftool -tab -d $DATE_FORMAT -json -DateTimeOriginal "$INPUT_FILE" | jq --raw-output '.[].DateTimeOriginal.val')
	OUTPUT_FILE_NAME=$(exiftool -tab -d $OUTPUT_DATE_FORMAT -json -DateTimeOriginal "$INPUT_FILE" | jq --raw-output '.[].DateTimeOriginal.val')
	DATA_TYPE="original"
	if [ "$DATE" == "null" ]
	then
		DATE=$(exiftool -tab -d $DATE_FORMAT -json -MediaCreateDate "$INPUT_FILE" | jq --raw-output '.[].MediaCreateDate.val')
		OUTPUT_FILE_NAME=$(exiftool -tab -d $OUTPUT_DATE_FORMAT -json -MediaCreateDate "$INPUT_FILE" | jq --raw-output '.[].MediaCreateDate.val')
		DATA_TYPE="create"
	fi
	if [ "$DATE" == "null" ]
	then
		DATE=$(exiftool -tab -d $DATE_FORMAT -json -ModifyDate "$INPUT_FILE" | jq --raw-output '.[].ModifyDate.val')
		OUTPUT_FILE_NAME=$(exiftool -tab -d $OUTPUT_DATE_FORMAT -json -ModifyDate "$INPUT_FILE" | jq --raw-output '.[].ModifyDate.val')
		DATA_TYPE="modify"
	fi
	echo -e "\n$INPUT_FILE - data: $DATE"
	if [ ! -z "$DATE" ]
	then
		Y=$(echo $DATE | sed -E "s/([0-9]*):([0-9]*):([0-9]*)/\\1/")
		M=$(echo $DATE | sed -E "s/([0-9]*):([0-9]*):([0-9]*)/\\2/")
		D=$(echo $DATE | sed -E "s/([0-9]*):([0-9]*):([0-9]*)/\\3/")
#		echo "Rok: $Y Miesiąc: $M Dzień: $D"
		if [ "$Y" -gt 0 ] & [ "$M" -gt 0 ] & [ "$D" -gt 0 ]
		then
			OUTPUT_DIR=${DESTINATION}/${Y}/${Y}${M}/${Y}${M}${D}
			echo "Output directory: $OUTPUT_DIR"
			if [ ! -d "$OUTPUT_DIR" ]
			then
				mkdir -pv ${OUTPUT_DIR}
			fi
			#skopiowanie pliku
			cp "$INPUT_FILE" "$OUTPUT_DIR"
			#zmiana nazwy pliku w katalogu docelowym
			OUTPUT_PATH="${OUTPUT_DIR}/${OUTPUT_FILE_NAME}.${INPUT_FILE_EXTENSION}"
			case $DATA_TYPE in
				"original")
					exiftool "-FileName<DateTimeOriginal" -d "%Y%m%d_%H%M%S%%-c.%%e" ${OUTPUT_DIR}/${INPUT_FILE_NAME}
					echo "Typ daty: $DATA_TYPE. Nowa ścieżka pliku: $OUTPUT_PATH"
					;;
				"create")
					exiftool "-FileName<MediaCreateDate" -d "%Y%m%d_%H%M%S%%-c.%%e" ${OUTPUT_DIR}/${INPUT_FILE_NAME}
					echo "Typ daty: $DATA_TYPE. Nowa ścieżka pliku: $OUTPUT_PATH"
					;;
				"modify")
					exiftool -tab "-FileName<ModifyDate" -d "%Y%m%d_%H%M%S%%-c.%%e" ${OUTPUT_DIR}/${INPUT_FILE_NAME}
					echo "Typ daty: $DATA_TYPE. Nowa ścieżka pliku: $OUTPUT_PATH"
					;;
			esac			
			#jeśli było przenieś - skasowanie pliku w katalogu źródłowym
			if [ "$TASK" == "Przenieś" ]
			then
				rm "$INPUT_FILE"
				echo "Oryginalny plik został usunięty."
			fi
		else
			echo "UWAGA! '$INPUT_FILE' nie zawiera informacji o dacie."
			zenity --warning --text="UWAGA! '$INPUT_FILE' nie zawiera informacji o dacie."
		fi
	else
		echo "UWAGA! '$INPUT_FILE' nie zawiera informacji o dacie."
		zenity --warning --text="UWAGA! '$INPUT_FILE' nie zawiera informacji o dacie."
	fi

done

#jeśli katalog źródłowy jest pusty, usuń
if [ "$TASK" == "Przenieś" ] 
then
	rmdir --ignore-fail-on-non-empty $SOURCE
fi

case $TASK in
	"Kopiuj")
		echo -e "\nUkończono kopiowanie."
		zenity --info --text="Ukończono kopiowanie."
		;;
	"Przenieś")
		echo -e "\nUkończono przenoszenie. Jeśli katalog źródłowy był pusty, został usunięty."
		zenity --info --text="Ukończono przenoszenie. Jeśli katalog źródłowy był pusty, został usunięty."
		;;
	*) 
		echo -e "\nCoś poszło nie tak..."
		zenity --error --text="Coś poszło nie tak..."
		;;
esac

#Ad. Obsługa spacji w nazwach plików
IFS=$SAVEIFS
