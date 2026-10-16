#!/usr/bin/env python3
"""Validate authored chemistry and compile its numeric tables into ignored build/."""
import argparse
import json
from pathlib import Path

def compile_catalog(source, output):
    catalog = json.loads(source.read_text())
    assert catalog["version"] == 1
    species = catalog["external_species"]
    assert len(species) <= 32 and [s["id"] for s in species] == list(range(len(species)))
    assert len({s["key"] for s in species}) == len(species)
    for reaction in catalog["modules"]:
        if "action" in reaction:
            continue
        mass = potential = 0.0
        potential += reaction["atp"]
        for sign, side in [(1, "outputs"), (-1, "inputs")]:
            for key, coefficient in reaction[side].items():
                assert coefficient > 0
                definition = catalog["species"][key]
                mass += sign * coefficient * definition["material"]
                potential += sign * coefficient * definition["potential"]
        assert abs(mass) < 1e-8, reaction["id"]
        assert potential <= 1e-8, reaction["id"]
    def values(key):
        return ", ".join(repr(float(item[key])) for item in species)
    materials = [catalog["species"].get(s["key"], {}).get("material", 0 if s["id"] in [1,3] else 1) for s in species]
    content = ("#pragma once\n#include <array>\n#include <algorithm>\nnamespace primordia_chemistry {\n"
        f"inline constexpr int species_count = {len(species)};\n"
        f"inline constexpr std::array<double,species_count> radii = {{{values('radius')}}};\n"
        f"inline constexpr std::array<double,species_count> decay = {{{values('decay')}}};\n"
        f"inline constexpr std::array<double,species_count> material = {{{', '.join(map(str,materials))}}};\n"
        f"inline constexpr double toxin_damage_per_unit = {float(catalog['combat']['toxin_damage_per_unit'])};\n"
        f"inline constexpr double merge_limit = {catalog['ecology']['merge_limit']};\n"
        f"inline constexpr double nutrient_merge_limit = {catalog['ecology']['nutrient_merge_limit']};\n"
        f"inline constexpr double nutrient_binding_bonus = {catalog['ecology']['nutrient_binding_bonus']};\n"
        f"inline constexpr double nutrient_bonus_limit = {catalog['ecology']['nutrient_bonus_limit']};\n"
        "inline double nutrient_capacity(double a,double ac,double b,double bc){double total=a+b;double fuel=std::min(a,std::max(0.,ac))+std::min(b,std::max(0.,bc));if(fuel<total)return fuel;return total+std::min(total*nutrient_bonus_limit,std::max(0.,ac-a)+std::max(0.,bc-b)+std::min(a,b)*nutrient_binding_bonus);}\n"
        f"inline constexpr double carbon_capacity = {catalog['ecology']['carbon_capacity']};\n"
        "}\n")
    output.parent.mkdir(parents=True, exist_ok=True)
    if not output.exists() or output.read_text() != content:
        output.write_text(content)

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, default=Path(__file__).resolve().parents[1]/"data/chemistry.json")
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parents[1]/"build/native/chemical_catalog.h")
    args = parser.parse_args()
    compile_catalog(args.source, args.output)
