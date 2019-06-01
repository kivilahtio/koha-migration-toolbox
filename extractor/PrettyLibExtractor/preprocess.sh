#!/bin/bash

# Preprocess 3rd party DB dumps
# Translator phase must receive DB dumps in:
# - plain text
# - UTF-8
# - .csv-files in https://tools.ietf.org/html/rfc4180
#
# 3rd parties provide dumps in various degrees of compatibility
# so we have to try to manage with this inconsistency here
#

RAW_EXPORTS_DIR="RawExports"            #Where the table dumps provided by the 3rd party are put into, that need preprocessing
#PRETTY_EXPORTS_DIR="PrettyCircExports"  #Where the preprocessed table dumps are placed for the MMT::Transformer
PRETTY_EXPORTS_DIR="PrettyLibExports"
FT="csv" #Table dump file type

TRANSLATE=0
RENAME=1
NULL_TO_EMPTY=1
POST_CLEANUP=1

SUFFIX="" #After each preprocessing phase set the last known suffix, so other phases can pick up where the previous phase left off dynamically


test $(echo "$RAW_EXPORTS_DIR" | wc --chars) -lt 11 && echo "WARNING! \$RAW_EXPORTS_DIR='$RAW_EXPORTS_DIR' is too short! Is this really ok?" && exit 1000
test $(echo "$PRETTY_EXPORTS_DIR" | wc --chars) -lt 11 && echo "WARNING! \$PRETTY_EXPORTS_DIR='$PRETTY_EXPORTS_DIR' is too short! Is this really ok?" && exit 1000


function trimExtraSuffixes {
  echo $(echo "$1" | grep -Po "\w+\.$FT")
}


echo "Using a temporary directory to mutate the dumps without destroying the original versions"
SUFFIX="copy"
mkdir "$RAW_EXPORTS_DIR/tmp"
for f in "$RAW_EXPORTS_DIR/"*; do cp "$f" "$RAW_EXPORTS_DIR/tmp/"$(basename "$f")".$SUFFIX"; done;

if [ $RENAME -eq 1 ]; then
  echo "Renaming dbo_Table.$FT to Table.$FT"
  NEW_SUFFIX="rename"
  for f in "$RAW_EXPORTS_DIR/tmp/"*".$SUFFIX"; do echo "$f"; mv "$f" "$RAW_EXPORTS_DIR/tmp/"$(echo "$f" | grep -Po '(?<=_)\w+\.csv')".$NEW_SUFFIX"; done;
  SUFFIX="$NEW_SUFFIX"
fi

if [ $TRANSLATE -eq 1 ]; then
  echo "Translating from ISO-8859-1 to UTF-8"
  NEW_SUFFIX="translate"
  for f in "$RAW_EXPORTS_DIR/tmp/"*".$SUFFIX"; do echo "$f"; iconv -f ISO-8859-1 -t UTF-8 -o "$RAW_EXPORTS_DIR/tmp/"$(trimExtraSuffixes "$f")".$NEW_SUFFIX" $f; rm "$f"; done;
  SUFFIX="$NEW_SUFFIX"
fi

if [ $NULL_TO_EMPTY -eq 1 ]; then
  echo "Replacing null with '' in-place"
  for f in "$RAW_EXPORTS_DIR/tmp/"*".$SUFFIX"; do
    perl -i -ne '$_ =~ s/(?<=,)null(?=,)//gsm; print $_;' "$f"
    perl -i -ne '$_ =~ s/,null\s*$/,\n/; print $_;' "$f"
    perl -i -ne '$_ =~ s/^\s*null(?=,)//; print $_;' "$f"
  done
fi

echo "Finally move the table dumps for MMT::Transformer to digest"
for f in "$RAW_EXPORTS_DIR/tmp/"*".$SUFFIX"; do mv "$f" "$PRETTY_EXPORTS_DIR/"$(trimExtraSuffixes "$f"); done; #Drop the $SUFFIX

if [ $POST_CLEANUP -eq 1 ]; then
  echo "Cleaning tmp directory"
  test $(echo "$RAW_EXPORTS_DIR" | wc --chars) -lt 11 && echo "WARNING! \$RAW_EXPORTS_DIR='$RAW_EXPORTS_DIR' is too short! Not killing a potential system directory." && exit 1000
  rm -r "$RAW_EXPORTS_DIR/tmp" #This can go wrong if the path is broken
fi

