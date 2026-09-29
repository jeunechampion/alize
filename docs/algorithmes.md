# Les algorithmes d'Alizé, en deux lignes chacun

Tout dans Alizé est calculé : aucune image, aucun modèle 3D, aucun son n'est importé. Voici ce qui
tourne sous le capot, et d'où ça vient. Le document de conception complet contient le reste.

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

## La végétation (`scripts/world/tree_builder.gd`, `vegetation.gd`)

- **Colonisation d'espace** (Runions, Lane & Prusinkiewicz 2007). Des points de lumière sont semés
  dans le volume de la couronne ; à chaque itération, chaque bout de branche pousse vers la moyenne
  des points qui lui sont les plus proches, et les points atteints disparaissent. Les formes
  obtenues sont celles des vrais arbres : ramification irrégulière, branches qui contournent.
- **Modèle des tubes** (Murray 1926, utilisé par Runions). Le rayon d'une branche mère vaut la
  racine 2,5-ième de la somme des rayons^2,5 de ses filles : le tronc s'épaissit naturellement.
- **Placement**. Une grille de 13 m tremblée par hachage entier déterministe ; chaque emplacement
  reçoit un palmier (plage basse et plate), un arbre (collines humides, pas dans les cendres) ou
  rien, selon l'altitude, la pente et un bruit d'humidité.
- **Vent** (Sousa, GPU Gems 3 ch. 16). Dans le shader, chaque sommet est déplacé en proportion du
  carré de sa hauteur, avec une phase propre à chaque arbre ; les feuilles frémissent en plus.
- **Niveaux de détail**. Près de la caméra le maillage complet (700 à 1 200 triangles), au-delà de
  650 m une silhouette d'une vingtaine de triangles ; la répartition est refaite toutes les 0,5 s.

## L'oiseau (`scripts/bird/bird_mesh.gd`)

Corps, tête, bec, queue, ailes en deux segments et pattes sont des primitives assemblées ; le
battement, le plané, le freinage et le piqué sont des rotations des pivots d'épaule et de coude.

## Le vent sonore (`scripts/audio/wind_audio.gd`)

Bruit blanc filtré par un passe-bas à deux pôles dont la fréquence de coupure et le volume
suivent la vitesse air.
