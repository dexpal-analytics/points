use std::collections::BTreeMap;
use std::path::PathBuf;

use alloy::json_abi::{Function, JsonAbi};

use crate::abi::{DexPalCredits, DexPalPoints};

/// `forge build`'s output: beside the client in the points repository, in `contracts/` in DexPal's.
const OUTS: [&str; 2] = ["../out", "../../contracts/out"];

/// The suite as `forge build` writes it.
fn compiled(path: &str) -> JsonAbi {
    let manifest = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let found = OUTS.iter().map(|out| manifest.join(out).join(path)).find(|file| file.is_file());
    let file = found.unwrap_or_else(|| panic!("{path} is in none of {OUTS:?}: run `forge build` first"));
    let text = std::fs::read_to_string(&file).unwrap_or_else(|error| panic!("{}: {error}", file.display()));
    let artifact: serde_json::Value = serde_json::from_str(&text).expect("a forge artifact");
    serde_json::from_value(artifact["abi"].clone()).expect("an ABI")
}

/// Each binding names a function of the compiled contract by selector, with the same outputs and
/// mutability.
fn matches(ours: BTreeMap<String, Vec<Function>>, theirs: &JsonAbi) {
    for function in ours.values().flatten() {
        let found = theirs.functions().find(|compiled| compiled.selector() == function.selector());
        let compiled = found.unwrap_or_else(|| panic!("{} is not in the compiled ABI", function.signature()));
        let outputs = |f: &Function| f.outputs.iter().map(|output| output.ty.clone()).collect::<Vec<_>>();
        assert_eq!(outputs(function), outputs(compiled), "{}", function.signature());
        assert_eq!(function.state_mutability, compiled.state_mutability, "{}", function.signature());
    }
}

#[test]
fn credits_bindings_match_the_compiled_contract() {
    matches(DexPalCredits::abi::functions(), &compiled("DexPalCredits.sol/DexPalCredits.json"));
}

#[test]
fn points_bindings_match_the_compiled_contract() {
    matches(DexPalPoints::abi::functions(), &compiled("DexPalPoints2.sol/DexPalPoints.json"));
}

#[test]
fn the_selectors_are_the_ones_the_backend_was_planned_on() {
    let credits = [
        ("setCredits", "2695ee11"),
        ("state", "c19d93fb"),
        ("roundName", "01fd050d"),
        ("writer", "453a2abc"),
        ("pointsContractAddress", "001666c0"),
        ("bannedUsers", "728d7680"),
        ("balanceOfBatch", "4e1273f4"),
        ("totalSupply", "bd85b039"),
    ];
    let points = [
        ("creditsContractAddress", "a5abc607"),
        ("issuePoints", "809967d3"),
        ("balanceOf", "70a08231"),
        ("predictedBalanceOf", "642db41e"),
    ];
    for (functions, want) in
        [(DexPalCredits::abi::functions(), &credits[..]), (DexPalPoints::abi::functions(), &points[..])]
    {
        let got: Vec<_> = functions.values().flatten().map(|f| (f.name.clone(), f.selector().to_string())).collect();
        let want: Vec<_> = want.iter().map(|(name, selector)| (name.to_string(), format!("0x{selector}"))).collect();
        assert_eq!(sorted(got), sorted(want));
    }
}

fn sorted(mut pairs: Vec<(String, String)>) -> Vec<(String, String)> {
    pairs.sort();
    pairs
}
