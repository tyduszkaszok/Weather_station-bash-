#!/bin/bash

DEBUG=false

debug() {
    if [ "$DEBUG" = true ]; then
        echo "DEBUG: $1"
    fi
}

if [ "$3" == "--debug" ] || [ "$3" == "--verbose" ]; then
    DEBUG=true
    echo "Tryb debugowania włączony."
fi

echo "Proszę czekać..."

cache_dir="$HOME/.cache/meteo"
debug "Ścieżka do folderu .cache: $cache_dir"
mkdir -p "$cache_dir"

url1="https://danepubliczne.imgw.pl/api/data/synop"

debug "Adres danych poszczególnych stacji meteorologicznych: $url1"

data1=$(curl -s "$url1")

stacja_lista=()

for stacja in $(echo "$data1" | jq -r '.[].stacja' | sed 'y/ąćęłńóśźżĄĆĘŁŃÓŚŹŻ/acelnoszzACELNOSZZ/'); do
	stacja_lista+=("$stacja")
	debug "Nazwa stacji bez znaków: $stacja"
done

for stacja in $(echo "$data1" | jq -r '.[].stacja'); do
    stacja_lista_pol+=("$stacja")
	debug "Nazwa stacji ze znakami: $stacja"
done

if [ "$1" == "--city" ]; then
    if [ -z "$2" ]; then
        echo "Podaj nazwę miasta jako drugi argument, np.: ./meteo.sh --city Warszawa"
        exit 1
    else
        miasto=$2
		debug "Wpisane miasto: $miasto"
    fi
elif [ "$1" == "--help" ]; then
	echo ""
	echo "Użycie: ./meteo.sh --city NazwaMiasta"
	echo "Jeśli nazwa miasta jest dwuczłonowa, zapisz ją w formie Nazwa_Miasta"
	echo ""
	exit 1	
else
    echo "Skorzystaj z --help."
    exit 1
fi

miasto_pl=$miasto

debug "Przypisano zmiennej miasto_pl miasto ze znakami polskimi."

miasto=$(echo "$miasto" | iconv -f utf-8 -t ascii//TRANSLIT)

debug "Konwersja miasta na brak znaków."

url2="https://nominatim.openstreetmap.org/search?q=$miasto&format=json"

debug "Adres dla podanego miasta: $url2"

data2=$(curl -s "$url2")

debug "Pobrano zawartość spod adresu."

szerokosc=$(echo "$data2" | jq -r '.[0].lat')
debug "Szerokość geograficzna podanego miasta: $szerokosc"
dlugosc=$(echo "$data2" | jq -r '.[0].lon')
debug "Długość geograficzna podanego miasta: $dlugosc" 
st_min_url="https://nominatim.openstreetmap.org/search?q=${stacja_lista[0]}&format=json"
debug "Adres dla pierwszego miasta z listy: $st_min_url"
st_min_data=$(curl -s "$st_min_url")
debug "Pobrano zawartość spod adresu."


min_lat=$(echo "$st_min_data" | jq -r '.[0].lat')
debug "Szerokość pierwszego miasta z listy: $min_lat"
min_lon=$(echo "$st_min_data" | jq -r '.[0].lon')
debug "Długość pierwszego miasta z listy: $min_lon"

dist () {
	local min_lat=$1
    local min_lon=$2
	local szerokosc=$3
    local dlugosc=$4

    local result=$(echo "($min_lat - $szerokosc) * ($min_lat - $szerokosc) + ($min_lon - $dlugosc) * ($min_lon - $dlugosc)" | bc)

    echo "$result"
}

min_num=$(dist "$min_lat" "$min_lon" "$szerokosc" "$dlugosc")
debug "Pierwszy dystans: $min_num"

min_stacja=${stacja_lista[0]}

if [ "$(ls -A $cache_dir)" ]; then
	debug "Uruchomienie pętli - istnieje już folder .cache."
    for index in "${!stacja_lista[@]}"; do
        stacja="${stacja_lista[index]}"
        path="$cache_dir/$stacja.json"
        lat=$(jq -r '.lat' "$path")
        lon=$(jq -r '.lon' "$path")
        num=$(dist "$lat" "$lon" "$szerokosc" "$dlugosc")

        if [ "$(echo "$num < $min_num" | bc)" -eq 1 ]; then
            min_num=$num
            min_stacja=$stacja
            min_index=$index
			debug "Znaleziono nową najmniejszą odległość: $min_num"
        fi
    done
else
	debug "Uruchomienie pętli - folder .cache nie istnieje."
    for index in "${!stacja_lista[@]}"; do
        stacja="${stacja_lista[index]}"
        st_min_url="https://nominatim.openstreetmap.org/search?q=${stacja}&format=json"
        debug "Adres zapytania: $st_min_url"
		st_min_data=$(curl -s "$st_min_url")
		debug "Pobrano dane."
		sleep 1
		echo "Proszę czekać..."
        lat=$(echo "$st_min_data" | jq -r '.[0].lat')
        lon=$(echo "$st_min_data" | jq -r '.[0].lon')
        num=$(dist "$lat" "$lon" "$szerokosc" "$dlugosc")
        cache_file="$cache_dir/$stacja.json"
		debug "Ścieżka do pliku: $cache_file"
        echo "{\"stacja\": \"$stacja\", \"lat\": \"$lat\", \"lon\": \"$lon\"}" > "$cache_file"

        if [ "$(echo "$num < $min_num" | bc)" -eq 1 ]; then
            min_num=$num
            min_stacja=$stacja
            min_index=$index
			debug "Znaleziono nową najmniejszą odległość: $min_num"
        fi
    done
fi

echo "Podane miasto: $miasto_pl"

miasto_pol="${stacja_lista_pol[min_index]}"

url="https://danepubliczne.imgw.pl/api/data/synop"

response=$(curl -s "$url")

if [ $? -eq 0 ]; then
    if command -v jq &> /dev/null; then
        miasto_data=$(echo "$response" | jq -r ".[] | select(.stacja == \"$miasto_pol\")")
        echo "Dane pogodowe dla $miasto_pol:"
        echo "$miasto_data" | jq
		debug "Zakończono pomyślnie."
    else
        echo "jq nie jest zainstalowany. Zainstaluj jq, aby lepiej przetworzyć dane JSON."
        echo "Dane pogodowe dla $miasto_pol:"
        echo "$response"
		debug "Błąd."
    fi
else
    echo "Błąd podczas pobierania danych z API IMGW."
	debug "Błąd."
fi
	
