# Les algorithmes d'Alizé, en deux lignes chacun

Le relief, la mer, le ciel, le vent, le vol et le placement de chaque plante sont calculés. Les
modèles 3D (arbres, plantes, oiseau, rochers) et les textures de sol sont des œuvres d'artistes
sous licence libre (voir `assets/CREDITS.md`) : le jeu les assemble, les habille et les éclaire.
Voici ce qui tourne sous le capot, et d'où ça vient. Le document de conception contient le reste.

## L'île (`scripts/world/island_generator.gd`)

- **Bruit fractal** (Perlin 1985 ; Musgrave 1989). On additionne plusieurs couches de bruit lisse, de
  plus en plus fines et de plus en plus faibles : le résultat ressemble à un relief naturel. La
  variante « ridged » (crêtes) donne les arêtes de montagne.
- **Déformation de domaine** (Quilez). Avant de lire le bruit, on décale légèrement les coordonnées
  avec un autre bruit : les formes se tordent et perdent leur régularité.
- **Trait de côte**. La distance au centre est multipliée par un bruit basse fréquence : le cercle
  de départ devient une côte à baies et à caps.
- **Volcan**. Un cône analytique lissé, avec un cratère creusé au sommet ; le plus haut des deux
  reliefs (montagne ou cône) l'emporte.
- **Plages**. Les altitudes entre 0 et 20 m sont compressées (courbe en puissance) : les pentes
  douces s'étalent en sable.
- **Fond marin**. Plateau récifal peu profond (le lagon turquoise), patates de corail, puis tombant
  vers le grand fond.
- **Déterminisme**. Toutes les valeurs aléatoires sortent d'un générateur initialisé par la seed :
  même mot, même île, sur toutes les machines. L'empreinte de l'île est vérifiée par les tests.

- **Rivières**. Trois à cinq sources sur les flancs du volcan ; chaque cours d'eau descend la ligne
  de plus grande pente avec un peu d'inertie et de méandres (bruit), jusqu'à la mer. Le niveau de
  l'eau ne remonte jamais ; le lit est creusé dans le relief (chenal parabolique, berges à 30 %),
  et une carte de distance aux rivières sert au sol (boue) et aux plantes (bananiers, bambous).

L'érosion hydraulique (Mei, Decaudin & Hu 2007) viendra avec le module natif, à l'étape « archipel ».

## L'océan (`shaders/ocean.gdshader`)

- **Vagues de Gerstner** (Gerstner 1802 ; Tessendorf 2001). Chaque point de la surface tourne sur
  un petit cercle : les crêtes sont pointues, les creux arrondis, comme une vraie houle. Quatre
  trains de vagues de longueurs différentes se superposent ; leur vitesse suit la relation de
  dispersion de l'eau profonde (c = √(g/k)).
- **Profondeur réelle**. Le shader lit le relief de l'île sous chaque point : la couleur passe du
  turquoise au bleu profond par absorption exponentielle, et l'écume apparaît là où l'eau a moins
  de 3 m. Les vagues s'amortissent dans le lagon.
- **Vaguelettes**. Deux couches de bruit qui défilent avec le vent perturbent la normale : c'est ce
  qui fait scintiller le soleil sur l'eau.

## Le ciel (`shaders/sky.gdshader`, `scripts/world/atmosphere.gd`)

- **Diffusion de Rayleigh et de Mie** (Nishita 1993 ; O'Neil 2005). La lumière du soleil est
  diffusée par les molécules d'air (surtout le bleu : le ciel est bleu, le soleil couchant rouge) et
  par les aérosols (le halo autour du soleil). Le shader intègre cette diffusion le long de chaque
  rayon de vue, avec des pas courts près de l'observateur et longs au loin.
- **Position du soleil** (Meeus 1991). Calculée pour une latitude de 15° nord à l'équinoxe : à
  midi le soleil est presque au zénith, il se lève plein est.
- **Cohérence**. La couleur du soleil, la brume et la lumière ambiante sont calculées par le même
  modèle que le ciel, côté processeur, pour que tout s'accorde à chaque heure.
- **Nuit**. Étoiles et Voie lactée générées par hachage.

## Le vent (`scripts/world/wind.gd`, `thermal.gd`)

- **Alizé**. Un vent de base régulier d'est.
- **Ascendance de pente**. Le vent qui rencontre un relief est dévié vers le haut : la composante
  verticale vaut le produit du vent horizontal par la pente, atténué avec la hauteur.
- **Thermiques** (Allen, NASA 2006). Colonne d'air chaud au profil en cloche, couronne
  descendante autour, montée progressive depuis la base, extinction au sommet, inclinée par le vent.
- **Gradient au ras des vagues** (Rayleigh 1883). Le vent est plus faible sous 20 m : c'est ce
  gradient qu'exploite le vol dynamique des albatros.

## Le vol (`scripts/bird/flight_model.gd`)

- **Portance et traînée** (Pennycuick 2008). L = ½ρv²S·CL et D = ½ρv²S·CD, avec CD = CD0 +
  CL²/(π·e·AR) : la polaire parabolique d'une aile d'allongement AR. Les valeurs sont celles d'un
  fou à pieds rouges (1 kg, 0,14 m² d'aile, allongement 8).
- **Décrochage**. Au-delà de 15° d'incidence, la portance s'effondre : l'oiseau tombe et reprend.
- **Virage**. On s'incline ; la portance inclinée fournit la force centripète. Pas de gouvernail.
- **Battement**. Une poussée limitée par la puissance disponible (≈ 32 W) : efficace à basse
  vitesse, faible à haute vitesse, et coûteuse en énergie.
- **Finesse**. Théorique : 12. Mesurée dans le jeu : environ 10 (le trim n'est pas au meilleur
  plané). Vitesse de décrochage : 8,7 m/s.

## La végétation (`scripts/world/vegetation.gd`, `asset_library.gd`, `shaders/vegetation.gdshader`)

- **Modèles d'artistes**. Vingt-six espèces (cocotier, dattier, chêne, grand arbre de canopée,
  acacia, cyprès à mousse, frangipanier, bananier, bambou, fougères, monstera, hibiscus, herbes,
  arbustes, rochers…) viennent de Sketchfab (CC-BY) et Poly Haven (CC0). Chaque glTF est aplati en
  un seul maillage (transformations cuites dans les sommets, surfaces regroupées par matériau) et
  ses matériaux sont convertis vers notre shader : mêmes textures, découpe alpha des feuilles, vent.
- **Placement**. Grille de 6,5 m tremblée par hachage entier déterministe (Wang) ; chaque
  emplacement tire une espèce selon l'altitude, la pente, un bruit d'humidité, la distance au
  cratère et aux rivières. Densité de forêt fermée : environ 0,5 arbre par cellule de 42 m², des
  couronnes de 8 à 18 m qui se chevauchent. Le calcul est réparti sur tous les cœurs par rangées.
- **Rendu en masse**. Un MultiMesh par morceau de 200 m et par espèce : le moteur trie ce qui est
  hors champ et choisit un niveau de détail (meshoptimizer, généré au chargement) par morceau.
  Le sous-bois n'existe que dans un rayon de 160 m autour de la caméra (morceaux de 64 m créés
  et détruits à la volée).
- **Imposteurs** (Brucks 2018, simplifié). Au-delà de 320 m, chaque arbre devient un panneau face
  à la caméra. Un atlas par espèce (8 azimuts × 5 élévations, albédo et normales, cuit hors ligne
  par `tools/bake_impostors.gd`) ; le shader reprojette le point du panneau dans le repère des
  quatre vues voisines et les mélange, puis éclaire avec les normales : l'arbre lointain réagit
  au soleil et à l'heure comme le vrai.
- **Anti-érosion des feuilles**. Les mipmaps moyennent l'alpha : au loin les feuilles disparaissent.
  On relève l'alpha proportionnellement au niveau de mipmap (calculé depuis les dérivées des UV).
- **Vent** (Sousa, GPU Gems 3 ch. 16). Déplacement en carré de la hauteur, phase par instance,
  frémissement des feuilles ; le temps et la direction du vent sont des uniformes globaux.

## Le sol (`shaders/terrain.gdshader`, `scripts/world/terrain_textures.gd`)

- **Tableaux de textures**. Neuf textures Poly Haven (sable sec et mouillé, herbe, sous-bois,
  hauteurs, roche, basalte, fond du lagon, boue) empilées en trois `Texture2DArray` (albédo,
  normales, AO-rugosité) : un échantillonneur par carte.
- **Couches**. Les mêmes règles qu'avant (altitude, pente, bruits) donnent un poids par couche ;
  projection au sol par les coordonnées monde, triplanaire pour la roche des falaises.
- **Palette**. Le détail de chaque texture est gardé, sa couleur moyenne est remplacée par celle
  de la palette « réalisme stylisé tropical » (herbe saturée, sable clair).

## L'oiseau (`scripts/bird/bird_model.gd`)

Le goéland de Dayvable (Sketchfab, CC-BY), squelette de 15 os. Son animation contient un cycle de
battement et une tenue de plané : on en découpe trois animations (battement en boucle à 2,4×,
plané, freinage ailes relevées) mélangées selon l'état du vol, puis on retouche des os par-dessus
(tête vers la visée, queue au freinage, ailes repliées le long du corps au sol).

## Le vent sonore (`scripts/audio/wind_audio.gd`)

Bruit blanc filtré par un passe-bas à deux pôles dont la fréquence de coupure et le volume
suivent la vitesse air.
