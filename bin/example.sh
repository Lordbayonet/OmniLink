#!/bin/bash
source venv/bin/activate
`which python3` predictions.py "$1"  output.csv --model model1 --submodel lgbm  --target Protein_Number --pdf result.pdf