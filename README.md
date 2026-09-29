# Alizé

Un oiseau, un archipel infini, le vent pour seul moteur.

Alizé est un jeu d'exploration : tu incarnes un fou à pieds rouges qui grandit, de poussin à ancien,
dans un monde d'îles tropicales généré à l'infini à partir d'une seed. Le vol repose sur la vraie
physique (portance, traînée, thermiques, ascendances de pente, vol dynamique), le monde sur les
algorithmes de la science réelle (bruit fractal, rivières par descente de pente, vagues de Gerstner,
diffusion atmosphérique, boids). Les arbres, les plantes et l'oiseau sont des modèles d'artistes
sous licence libre (Sketchfab CC-BY, Poly Haven CC0), listés dans `assets/CREDITS.md`.

## Jouer

Les versions téléchargeables (Mac, Windows, Linux) sont publiées dans les
[Releases](https://github.com/jeunechampion/alize/releases) à chaque étape.

Commandes (clavier + souris) :

| Action | Touche |
| --- | --- |
| Diriger | Souris |
| Battre des ailes | Espace (maintenu) |
| Freiner, cabrer | S ou clic droit |
| Piquer | W |
| Roulis fin | A / Q et D |
| Se poser, décoller | E |
| Caméra 1re / 3e personne | V |
| Vitesse du temps | T |
| Nouvelle île (seed suivante) | N |
| Recommencer | R |
| Aide | H |
| Libérer la souris | Échap |

Manette : stick gauche pour diriger, A pour battre des ailes, gâchettes pour freiner et piquer.

## Développement

Le jeu est fait avec [Godot 4.7](https://godotengine.org) (open source, MIT). Le projet s'ouvre
directement dans l'éditeur Godot, et se lance en ligne de commande :

```
godot --path . 
```

Les modèles glTF sont dans `assets/sketchfab/` et `assets/polyhaven/` (ce dernier est rempli par le
workflow GitHub « Récupérer les ressources Poly Haven » depuis `assets/manifest.json`). Les atlas
d'imposteurs (arbres lointains) se recuisent avec :

```
xvfb-run godot --path . --rendering-method gl_compatibility tools/bake_impostors.tscn
```

Catalogue des espèces et de l'oiseau (captures) : `tests/catalog.tscn` avec `--out=`, `--species=`,
`--impostors`, `--bird`.

Tests sans fenêtre (générateur d'île, modèle de vol) :

```
godot --headless --path . -s tests/run_tests.gd
```

Vol automatique avec captures d'écran (utilisé pour vérifier le rendu) :

```
godot --path . -- --autotest --autotest-dir=/tmp/alize_shots
```

Le document de conception complet (décisions, systèmes, fiches algorithmes) est tenu à part ;
[docs/algorithmes.md](docs/algorithmes.md) explique en deux lignes chaque algorithme utilisé.

Sur Mac, l'application n'est pas notariée par Apple (aucun compte payant) : au premier lancement,
clic droit → Ouvrir, ou Réglages Système → Confidentialité et sécurité → « Ouvrir quand même ».

## Licence

MIT. Tout le contenu est procédural : aucune ressource tierce.
