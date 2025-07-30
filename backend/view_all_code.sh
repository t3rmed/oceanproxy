#!/bin/bash
echo "# OceanProxy Backend Code Dump"
echo "# Generated on $(date)"
echo "# ================================"

for file in $(find . -name "*.go" -o -name "*.env" | sort); do
    echo ""
    echo "## File: $file"
    echo "## ================================"
    cat "$file"
    echo ""
    echo "## End of $file"
    echo "## ================================"
done
