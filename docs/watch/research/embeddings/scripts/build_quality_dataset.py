#!/usr/bin/env python3
"""Build the 10 follow topics x 30 paragraphs benchmark dataset for ParTake Parliament watch research.

Topics cover 10 core Canadian parliamentary debate subjects.
30 paragraphs (17 English, 13 French) each ~100-140 words, modeled on Hansard/committee speeches.
Each topic has exactly 3 ground-truth relevant paragraphs in the corpus.
"""

import json
from pathlib import Path

TOPICS = [
    {
        "id": "T01",
        "title": "Housing affordability and rental costs",
        "query_en": "housing affordability and rental costs",
        "query_fr": "l'abordabilité du logement et le coût des loyers",
        "short_topic": "housing affordability",
        "relevant_paragraph_ids": ["P01", "P02", "P03"]
    },
    {
        "id": "T02",
        "title": "Carbon pricing and industrial emissions policy",
        "query_en": "carbon pricing and industrial emissions policy",
        "query_fr": "la tarification du carbone et les émissions industrielles",
        "short_topic": "carbon pricing",
        "relevant_paragraph_ids": ["P04", "P05", "P06"]
    },
    {
        "id": "T03",
        "title": "Official languages and French immersion education support",
        "query_en": "official languages and French immersion education support",
        "query_fr": "les langues officielles et le soutien à l'immersion française",
        "short_topic": "official languages",
        "relevant_paragraph_ids": ["P07", "P08", "P09"]
    },
    {
        "id": "T04",
        "title": "National defence procurement and NATO spending commitment",
        "query_en": "national defence procurement and NATO spending commitment",
        "query_fr": "l'approvisionnement de la défense nationale et les dépenses de l'OTAN",
        "short_topic": "national defence procurement",
        "relevant_paragraph_ids": ["P10", "P11", "P12"]
    },
    {
        "id": "T05",
        "title": "Healthcare transfers and emergency room wait times",
        "query_en": "healthcare transfers and emergency room wait times",
        "query_fr": "les transferts en santé et le temps d'attente aux urgences",
        "short_topic": "healthcare transfers",
        "relevant_paragraph_ids": ["P13", "P14", "P15"]
    },
    {
        "id": "T06",
        "title": "Reconciliation and indigenous clean drinking water advisories",
        "query_en": "reconciliation and indigenous clean drinking water advisories",
        "query_fr": "la réconciliation et les avis d'ébullition d'eau chez les Premières Nations",
        "short_topic": "clean drinking water for First Nations",
        "relevant_paragraph_ids": ["P16", "P17", "P18"]
    },
    {
        "id": "T07",
        "title": "Bill C-5 and criminal justice sentencing reforms",
        "query_en": "Bill C-5 and criminal justice sentencing reforms",
        "query_fr": "le projet de loi C-5 et la réforme des peines criminelles",
        "short_topic": "Bill C-5",
        "relevant_paragraph_ids": ["P19", "P20", "P21"]
    },
    {
        "id": "T08",
        "title": "Supply management and agricultural trade negotiations",
        "query_en": "supply management and agricultural trade negotiations",
        "query_fr": "la gestion de l'offre et les négociations commerciales agricoles",
        "short_topic": "supply management",
        "relevant_paragraph_ids": ["P22", "P23", "P24"]
    },
    {
        "id": "T09",
        "title": "Border security, asylum claims and immigration levels",
        "query_en": "border security, asylum claims and immigration levels",
        "query_fr": "la sécurité frontalière, les demandes d'asile et les cibles d'immigration",
        "short_topic": "border security and immigration levels",
        "relevant_paragraph_ids": ["P25", "P26", "P27"]
    },
    {
        "id": "T10",
        "title": "Critical minerals strategy and electric vehicle supply chain",
        "query_en": "critical minerals strategy and electric vehicle supply chain",
        "query_fr": "la stratégie sur les minéraux critiques et la chaîne de véhicules électriques",
        "short_topic": "critical minerals strategy",
        "relevant_paragraph_ids": ["P28", "P29", "P30"]
    }
]

PARAGRAPHS = [
    # T01: housing affordability
    {
        "id": "P01", "topic_id": "T01", "lang": "en",
        "text": "Mr. Speaker, across our nation, families are facing an unprecedented housing affordability crunch. Young workers and newcomers who did everything right find themselves priced out of homeownership, while average monthly rents in cities like Toronto, Vancouver, and Halifax continue to rise beyond the reach of normal wages. The government talks about funding announcements and bureaucratic programs, but after nearly a decade in power, the reality is that home construction cannot keep pace with population growth. We need municipalities to cut red tape, speed up zoning approvals, and ensure builders can actually break ground on high-density rental units near transit hubs. Without real fiscal restraint and incentives for home building, an entire generation of Canadians will be permanently locked out of owning a home in their own communities."
    },
    {
        "id": "P02", "topic_id": "T01", "lang": "en",
        "text": "The minister must answer why rent inflation remains stubbornly high despite multiple housing strategies announced in federal budgets. Low-income seniors on fixed pensions are receiving eviction notices because corporate landlords are converting apartment buildings into luxury developments. Our community housing advocates report that waitlists for non-market and cooperative housing now stretch over several years in major urban centres. We are asking the federal government to establish a tenant protection acquisition fund that allows non-profit housing providers to purchase aging rental properties before private equity firms buy them. If we truly treat shelter as a fundamental human right rather than a speculative asset class, we must immediately expand federal investments in non-market housing to protect vulnerable tenants from skyrocketing market rents."
    },
    {
        "id": "P03", "topic_id": "T01", "lang": "fr",
        "text": "Monsieur le Président, la crise du logement frappe durement les familles québécoises et les locataires de nos régions. Les hausses de loyer atteignent des sommets historiques, et le taux d'inoccupation dans plusieurs villes universitaires est tombé sous la barre du un pour cent. Pendant ce temps, le gouvernement fédéral tarde à transférer sans condition les fonds promis pour le logement social et communautaire. Les organismes sans but lucratif et les coopératives d'habitation sont prêts à construire des milliers de logements abordables dès maintenant, mais ils sont paralysés par la lenteur administrative fédérale. Il est temps que le ministre respecte les compétences du Québec, débloque immédiatement les enveloppes financières et permette aux intervenants locaux de bâtir des toits abordables pour nos aînés et nos familles vulnérables."
    },

    # T02: carbon pricing and emissions
    {
        "id": "P04", "topic_id": "T02", "lang": "en",
        "text": "Mr. Speaker, the federal fuel charge is placing an unfair burden on rural families, small businesses, and agricultural producers who have no alternative to fossil fuels. In rural ridings, commuters must drive significant distances every day to get to work, medical appointments, and grocery stores. When the government increases the carbon tax, it cascades through the entire supply chain, raising the cost of shipping food, heating barns, and drying grain. Farmers cannot simply switch to electric combines or zero-emission grain dryers overnight because the technology is not commercially viable. The rebate cheques cited by the minister do not compensate for the compounding inflationary pressure felt by farm families. We demand the immediate repeal of the carbon tax on all farm fuels, heating fuels, and daily transportation necessities."
    },
    {
        "id": "P05", "topic_id": "T02", "lang": "en",
        "text": "Our government remains resolute in its commitment to addressing climate change through an effective, market-based carbon pricing mechanism that encourages industrial innovation. International evidence clearly demonstrates that putting a price on pollution is the most economically efficient way to reduce greenhouse gas emissions while driving private capital into clean technology. The industrial carbon pricing system holds our heaviest emitters accountable while returning ninety percent of fuel charge revenues directly to households in participating provinces through quarterly Canada Carbon Rebates. Independent analyses from Canadian economists consistently confirm that eight out of ten middle-class families receive more back in rebate payments than they pay in direct fuel costs. To abandon carbon pricing would be to abandon our emissions targets and cede leadership in the global clean energy transition."
    },
    {
        "id": "P06", "topic_id": "T02", "lang": "fr",
        "text": "Monsieur le Président, la lutte contre les changements climatiques exige une tarification rigoureuse des émissions industrielles et un plafonnement strict du secteur pétrolier et gazier. Le Québec a instauré son propre marché du carbone avec la Californie depuis plus d'une décennie, démontrant qu'il est tout à fait possible de réduire les émissions polluantes tout en maintenant une économie dynamique. Or, le gouvernement fédéral continue d'accorder des milliards de dollars de subventions et de crédits d'impôt aux multinationales des hydrocarbures pour des projets de captage du carbone non éprouvés. Si nous voulons respecter nos engagements de l'Accord de Paris, Ottawa doit cesser de subventionner les énergies fossiles et investir massivement dans l'efficacité énergétique, les transports collectifs électriques et les technologies propres d'avenir."
    },

    # T03: official languages and French immersion
    {
        "id": "P07", "topic_id": "T03", "lang": "en",
        "text": "Madam Speaker, linguistic duality is one of Canada's core founding principles, yet across the country parents face enormous barriers accessing French immersion education for their children. In British Columbia and Alberta, families line up overnight in lotteries hoping to secure a single spot in kindergarten French immersion classes, only to be turned away due to a chronic shortage of bilingual educators. The federal government must work collaboratively with the provinces and territorial school boards to recruit, train, and retain qualified French language teachers. Furthermore, post-secondary institutions offering French-language and bilingual degrees in minority communities need stable, predictable multi-year core funding. Investing in French second-language education not only strengthens national unity but also equips future generations of Canadian students with critical global professional opportunities."
    },
    {
        "id": "P08", "topic_id": "T03", "lang": "fr",
        "text": "Monsieur le Président, le déclin du français au Québec et dans les communautés francophones en situation minoritaire à travers le pays est un fait documenté par Statistique Canada. La Loi sur les langues officielles modernisée par le projet de loi C-13 devait enfin protéger le français comme langue officielle en péril et imposer des obligations linguistiques aux entreprises privées sous réglementation fédérale. Pourtant, dans les aéroports, les banques et les télécommunications à Montréal et dans l'Est de l'Ontario, le droit de travailler et d'être servi en français continue d'être bafoué quotidiennement. Le gouvernement refuse toujours d'assujettir ces entreprises à la Charte de la langue française. Nous exigeons que le commissaire aux langues officielles obtienne de véritables pouvoirs de sanction financière pour faire respecter la langue française."
    },
    {
        "id": "P09", "topic_id": "T03", "lang": "fr",
        "text": "Les francophones hors Québec, de l'Acadie jusqu'au Yukon, se battent quotidiennement pour préserver leurs écoles de langue française, leurs centres de la petite enfance et leurs hôpitaux communautaires. Sans un financement fédéral pérenne pour les infrastructures éducatives de la petite enfance, le taux d'assimilation linguistique continuera d'augmenter chez nos jeunes générations. Le gouvernement fédéral a le devoir constitutionnel d'appuyer l'épanouissement des communautés de langue officielle en situation minoritaire conformément à la partie sept de la loi. Nous demandons la mise en œuvre intégrale du Plan d'action pour les langues officielles, l'augmentation des bourses pour la formation des enseignants francophones et la création de guichets de services fédéraux véritablement bilingues dans toutes les régions désignées du Canada."
    },

    # T04: national defence and NATO spending
    {
        "id": "P10", "topic_id": "T04", "lang": "en",
        "text": "Mr. Speaker, our Canadian Armed Forces are facing an operational readiness crisis marked by severe recruiting shortfalls and aging military equipment. While our democratic allies in NATO are increasing their defence budgets well beyond two percent of gross domestic product, Canada remains among the lowest contributors in the alliance. Our military personnel are deployed on NATO missions in Eastern Europe with obsolete communication systems, limited air defence capabilities, and substandard living conditions at domestic bases. The defence policy update promised billions in new capital funding, but actual spending is repeatedly reprofiled and delayed to future fiscal years. Canada must immediately table a credible, binding plan to reach the NATO two percent benchmark, accelerate procurement of maritime patrol aircraft, and acquire modern submarines capable of operating under Arctic ice."
    },
    {
        "id": "P11", "topic_id": "T04", "lang": "en",
        "text": "Madam Speaker, defending Canadian sovereignty requires unprecedented modernization of our North American Aerospace Defense Command infrastructure in the High North. Arctic security can no longer be taken for granted as geopolitical competitors expand naval and aerial operations near our maritime boundaries. The government has committed nearly forty billion dollars over two decades to upgrade over-the-horizon radar arrays, modernize northern forward operating locations for CF-35 fighter jets, and enhance satellite surveillance over our vast maritime approaches. These vital procurement investments will create high-skilled aerospace engineering jobs across Ontario, Quebec, and Western Canada while guaranteeing our domestic defence readiness. We will ensure our brave women and men in uniform possess the advanced equipment and digital command networks required to defend Canada's northern territorial integrity alongside our American partners."
    },
    {
        "id": "P12", "topic_id": "T04", "lang": "fr",
        "text": "Monsieur le Président, la politique de défense nationale ne peut pas ignorer les retards chroniques dans le processus d'approvisionnement militaire et la vétusté de nos infrastructures navales. La flotte de frégates de patrouille de la Marine royale canadienne arrive rapidement en fin de vie utile, et le programme de navires de combat canadiens subit des dépassements de coûts de plusieurs milliards de dollars. De plus, nos troupes manquent de blindés modernes, de drones de reconnaissance et de systèmes de défense sol-air pour sécuriser nos déploiements en Lettonie. Le gouvernement fédéral doit éliminer les lourdeurs bureaucratiques au ministère des Services publics et de l'Approvisionnement afin d'accélérer la livraison des navires et de respecter nos engagements multilatéraux au sein de l'OTAN et du NORAD."
    },

    # T05: healthcare transfers and emergency rooms
    {
        "id": "P13", "topic_id": "T05", "lang": "en",
        "text": "Mr. Speaker, Canadian healthcare is in a state of crisis with emergency rooms forced to close overnight due to critical shortages of physicians and registered nurses. Patients in rural and suburban hospitals wait twelve to twenty-four hours on stretchers in hospital hallways just to receive basic emergency medical care. While provinces administer delivery under constitutional authority, the federal government slashed its proportional share of healthcare funding over successive decades. The bilateral health agreements signed last year offered modest investments, but they come with prescriptive federal reporting conditions that distract healthcare managers from patient care. We need a substantial, unconditional increase to the Canada Health Transfer so provincial health ministries can expand residency spots, recruit foreign-trained medical graduates, and retain exhausted frontline healthcare workers before the public system collapses completely."
    },
    {
        "id": "P14", "topic_id": "T05", "lang": "en",
        "text": "The Minister of Health must explain why millions of Canadians still lack access to a dedicated family physician or primary care nurse practitioner in their local neighbourhood. Without primary care access, manageable chronic conditions like diabetes and hypertension deteriorate until patients are forced to seek help in overcrowded hospital emergency departments. Our government has committed nearly two hundred billion dollars over ten years to transform provincial healthcare, tying federal funding directly to measurable improvements such as digital health records, reduced surgical backlogs, and mental health services. We are working closely with regulatory colleges to accelerate credential recognition for internationally trained doctors and nurses. Canadians expect public healthcare to be there when they need it, and we will hold provincial governments accountable for delivering transparent health outcomes."
    },
    {
        "id": "P15", "topic_id": "T05", "lang": "fr",
        "text": "Monsieur le Président, les salles d'urgence du Québec et des provinces débordent parce que les hôpitaux manquent cruellement de personnel infirmier et de places en soins de longue durée pour les personnes âgées. Le gouvernement fédéral perçoit la moitié des recettes fiscales de ce pays mais ne finance qu'environ vingt-deux pour cent des coûts réels de notre système de santé public. Les premiers ministres provinciaux ont réclamé à l'unanimité une hausse sans condition du Transfert canadien en matière de santé à hauteur de trente-cinq pour cent des dépenses. Au lieu de transférer l'argent qui revient de droit aux contribuables québécois, Ottawa persiste à vouloir imposer des normes et des indicateurs centralisateurs. Le gouvernement fédéral doit respecter l'autonomie des provinces et financer équitablement nos services de santé de première ligne."
    },

    # T06: indigenous reconciliation and water advisories
    {
        "id": "P16", "topic_id": "T06", "lang": "en",
        "text": "Madam Speaker, true reconciliation with Indigenous peoples cannot occur while dozens of First Nations communities still endure long-term boil water advisories that compromise basic human dignity. In many northern and remote reserves, families must boil tap water or rely on plastic bottles flown in at astronomical expense simply to bathe their children and prepare meals. Although the government promised in 2015 to eliminate all long-term drinking water advisories within five years, nine years later communities continue to face systemic infrastructure failures, inadequate water treatment plant funding, and a severe deficit of certified water system operators. We need dedicated, permanent statutory funding for First Nations water infrastructure maintenance and complete self-determination so Indigenous governments can operate, monitor, and maintain high-quality clean drinking water systems in their own territories."
    },
    {
        "id": "P17", "topic_id": "T06", "lang": "en",
        "text": "The Minister of Indigenous Services celebrated lifting several advisories, but failed to mention that many First Nations water systems remain at high risk of falling back into boil water status due to deferred maintenance. A water treatment facility is only as reliable as the ongoing operational budget and training provided to local community members. Furthermore, the government has repeatedly litigated against First Nations children in human rights tribunals over child welfare and basic services equity instead of implementing the Truth and Reconciliation Commission's Calls to Action. Reconciliation requires fulfilling treaty obligations, providing equitable funding for reserve housing and clean water, and transferring full jurisdiction over child and family services directly to Indigenous governing bodies without political hesitation or bureaucratic obstruction."
    },
    {
        "id": "P18", "topic_id": "T06", "lang": "fr",
        "text": "Monsieur le Président, le chemin vers la réconciliation avec les peuples autochtones passe nécessairement par l'accès universel à l'eau potable salubre et la reconnaissance du droit à l'autodétermination. Il est intolérable qu'en 2026, dans un pays aussi prospère que le Canada, des enfants autochtones grandissent dans des réserves sans eau courante potable pour boire et se laver. Les retards continuels dans le renouvellement des infrastructures de traitement des eaux usées et des usines de filtration reflètent des décennies de négligence coloniale. Le gouvernement fédéral doit respecter intégralement les principes de la Déclaration des Nations Unies sur les droits des peuples autochtones, transférer la pleine gestion des infrastructures aux communautés et financer de façon durable la formation des opérateurs locaux de traitement d'eau."
    },

    # T07: Bill C-5 and criminal justice
    {
        "id": "P19", "topic_id": "T07", "lang": "en",
        "text": "Mr. Speaker, the passage and implementation of Bill C-5 repealed mandatory minimum penalties for numerous firearm offences and drug-related crimes under the Criminal Code. The government claimed this legislation was designed to address systemic racism and overrepresentation of Indigenous and Black offenders in federal correctional institutions. However, removing mandatory sentences for offences involving firearms, robbery with a gun, and drive-by shootings has weakened deterrence and left communities vulnerable to repeat gang violence. Law enforcement associations and victims of crime groups warned parliament that mandatory penalties are essential for keeping violent offenders off our streets. We are calling for the immediate reinstatement of tough mandatory jail terms for violent gun crimes and an end to lenient bail and conditional sentencing orders that release repeat offenders into neighbourhoods."
    },
    {
        "id": "P20", "topic_id": "T07", "lang": "en",
        "text": "The Minister of Justice rightly defended Bill C-5 as evidence-based sentencing reform that restores judicial discretion to sentencing judges who can evaluate the unique circumstances of each case. Mandatory minimum penalties have been repeatedly struck down by appellate courts and the Supreme Court of Canada as unconstitutional cruel and unusual punishment under section twelve of the Charter. Decades of criminal justice research prove that mandatory sentences do not deter criminal conduct or reduce recidivism; instead, they disproportionately incarcerate marginalized and Indigenous individuals while clogging trial courts with constitutional challenges. By expanding the availability of conditional sentence orders and community-based restorative justice programs, Bill C-5 enables rehabilitation, reduces provincial prison overcrowding, and focuses punitive custody where it is truly warranted for dangerous offenders."
    },
    {
        "id": "P21", "topic_id": "T07", "lang": "fr",
        "text": "Monsieur le Président, la réforme du droit criminel et l'abolition des peines minimales obligatoires instaurées par le projet de loi C-5 soulèvent d'importantes inquiétudes auprès des corps policiers et des citoyens. En éliminant les peines d'emprisonnement obligatoires pour certaines infractions graves commises avec des armes à feu prohibées, cette mesure a restreint la capacité des tribunaux à envoyer un message clair de dissuasion contre le crime organisé. Bien que nous reconnaissions la nécessité de lutter contre la surreprésentation des minorités en milieu carcéral, la priorité absolue de la justice doit demeurer la protection du public et le respect des droits des victimes d'actes criminels. Le gouvernement fédéral doit réévaluer l'impact de ces réformes et resserrer les règles sur la libération sous caution pour les récidivistes violents."
    },

    # T08: supply management and dairy trade
    {
        "id": "P22", "topic_id": "T08", "lang": "en",
        "text": "Mr. Speaker, Canadian dairy, poultry, and egg producers rely on our system of supply management to earn a fair return from the market without relying on massive taxpayer subsidies. In three consecutive international trade agreements—CETA, CPTPP, and the USMCA—the previous federal administration made concessions that breached our domestic tariff-rate quotas, granting foreign producers unprecedented market access to our grocery shelves. While Parliament passed private member's legislation to legally prohibit future trade negotiators from making further market access concessions in supply-managed agricultural sectors, our farmers continue to wait for full, fair, and timely compensation packages. With rising feed costs, elevated fuel expenses, and high interest rates on farm loans, the federal government must guarantee that supply management remains completely non-negotiable in any forthcoming review of our North American trade pact."
    },
    {
        "id": "P23", "topic_id": "T08", "lang": "fr",
        "text": "Monsieur le Président, les producteurs laitiers du Québec et du Canada constituent le cœur économique de nos régions rurales. Le système de la gestion de l'offre assure la stabilité des prix, garantit aux consommateurs des produits laitiers et de volaille de haute qualité sans hormones de croissance, et permet aux fermes familiales de vivre dignement sans subventions étatiques directes. Pourtant, les gouvernements successifs ont utilisé nos quotas agricoles comme monnaie d'échange dans les traités de libre-échange avec l'Europe et les États-Unis. Le Bloc Québécois a fait adopter le projet de loi C-282 à la Chambre pour protéger intégralement la gestion de l'offre lors de toutes négociations commerciales futures. Le Sénat et le gouvernement doivent veiller à ce que ce rempart législatif entre en vigueur sans aucun affaiblissement."
    },
    {
        "id": "P24", "topic_id": "T08", "lang": "fr",
        "text": "Les éleveurs de volailles et les producteurs d'œufs de nos régions subissent les contrecoups des concessions tarifaires accordées dans les accords commerciaux internationaux ainsi que les coûts colossaux liés aux mesures de biosécurité face à la grippe aviaire. Les programmes d'indemnisation promis par le gouvernement fédéral pour compenser les brèches de marché de l'Accord Canada-États-Unis-Mexique accusent des retards de versement inacceptables. Nos producteurs agricoles ont besoin de certitude financière pour investir dans la modernisation de leurs poulaillers et la transition écologique de leurs exploitations. Nous exigeons que la ministre de l'Agriculture débloque immédiatement les compensations résiduelles et réaffirme son appui indéfectible à notre modèle agricole sous gestion de l'offre face aux pressions protectionnistes américaines."
    },

    # T09: border security and immigration
    {
        "id": "P25", "topic_id": "T09", "lang": "en",
        "text": "Mr. Speaker, our immigration system has lost public confidence because the government dramatically increased admission targets without planning for healthcare, transit, and housing capacity. Over the past three years, unprecedented surges in temporary foreign workers and international student visas created severe strains in communities across Ontario, British Columbia, and Quebec. Furthermore, backlogs at the Immigration and Refugee Board now exceed two hundred thousand claims, meaning genuine refugees wait years for decisions while failed applicants remain without deportation enforcement. We support orderly, legal immigration that matches labour market shortages and respects our humanitarian traditions. However, the federal government must tie overall immigration levels directly to available housing stock, close irregular border crossing loopholes, and restore integrity and administrative competence to Immigration, Refugees and Citizenship Canada."
    },
    {
        "id": "P26", "topic_id": "T09", "lang": "fr",
        "text": "Monsieur le Président, la gestion des frontières et l'accueil des demandeurs d'asile dépassent largement la capacité d'accueil du Québec et mettent à rude épreuve nos services publics, notamment nos écoles et nos banques alimentaires. Même après la fermeture officielle du chemin Roxham grâce à la modernisation de l'Entente sur les pays tiers sûrs, le nombre de demandeurs d'asile arrivant par les aéroports de Montréal et Toronto a explosé. Le Québec accueille une part disproportionnée des demandeurs d'asile au pays sans recevoir la pleine compensation financière des milliards de dollars déboursés pour leur hébergement d'urgence et leur soutien social. Le gouvernement fédéral doit répartir équitablement les demandeurs d'asile entre toutes les provinces canadiennes et accélérer le traitement des dossiers de permis de travail."
    },
    {
        "id": "P27", "topic_id": "T09", "lang": "fr",
        "text": "Le ministre de l'Immigration a annoncé une réduction des cibles de résidents permanents et temporaires, mais cette décision tardive témoigne d'une improvisation totale dans la planification démographique du pays. En délivrant des centaines de milliers de permis d'études et de travail temporaire sans concertation avec les provinces, le gouvernement fédéral a alimenté la spéculation immobilière et accentué la pression sur le réseau de santé. Nous demandons qu'Ottawa transfère au Québec tous les pouvoirs en matière d'immigration temporaire afin d'arrimer les admissions aux besoins réels du marché du travail québécois et aux impératifs de la francisation des nouveaux arrivants. Une politique d'immigration réussie doit être planifiée, rigoureuse et respectueuse de la cohésion sociale."
    },

    # T10: critical minerals and EV supply chain
    {
        "id": "P28", "topic_id": "T10", "lang": "en",
        "text": "Mr. Speaker, Canada possesses vast geological reserves of critical minerals like lithium, nickel, graphite, and rare earth elements that are essential for manufacturing electric vehicle batteries, wind turbines, and defence electronics. However, developing a new mining project in Northern Ontario or the Northwest Territories currently takes twelve to fifteen years due to overlapping federal, provincial, and territorial regulatory review processes. While foreign authoritarian regimes dominate the global processing of critical minerals, Canadian mining companies struggle to secure basic infrastructure like all-weather roads and clean electrical transmission grids to northern deposits. If Canada wants to secure its place as a green industrial powerhouse in the Western alliance, the government must streamline environmental impact assessments, invest in northern energy corridors, and protect domestic mining assets from hostile state-owned enterprises."
    },
    {
        "id": "P29", "topic_id": "T10", "lang": "en",
        "text": "Madam Speaker, our federal Critical Minerals Strategy has successfully attracted tens of billions of dollars in private capital for electric vehicle assembly and battery precursor plants in Ontario and Quebec. By leveraging our abundance of clean hydroelectric power and skilled manufacturing workforce, we are building an end-to-end domestic supply chain from mine to showroom. Through the Strategic Innovation Fund and investment tax credits for clean technology manufacturing, we are partnering with global automotive leaders to secure hundreds of thousands of well-paying union jobs for generations to come. This industrial transformation will drastically reduce transportation greenhouse gas emissions while ensuring North American manufacturing independence. We reject the short-sighted opposition approach that would cancel green manufacturing incentives and hand the future of automotive technology entirely to competitor nations."
    },
    {
        "id": "P30", "topic_id": "T10", "lang": "fr",
        "text": "Monsieur le Président, la filière québécoise des batteries et des minéraux critiques dans le parc industriel de Bécancour représente un modèle exceptionnel de transition énergétique et de développement industriel propre. Grâce à nos richesses minières en lithium, cobalt et graphite et à notre hydroélectricité renouvelable, le Québec est en voie de devenir un pôle mondial pour les composants de batteries de véhicules électriques. Toutefois, pour maximiser les retombées économiques locales, le gouvernement fédéral doit veiller à ce que la première et deuxième transformation des minerais s'effectue chez nous plutôt que d'exporter nos matières premières brutes. Ottawa doit investir dans la modernisation du port de Bécancour, appuyer les entreprises québécoises de recyclage des métaux stratégiques et soutenir la recherche universitaire sur les matériaux d'électrodes."
    }
]

def main():
    data = {
        "metadata": {
            "description": "Hand-labeled quality evaluation dataset: 10 Canadian Parliamentary follow topics x 30 speeches (17 EN, 13 FR)",
            "date": "2026-10-11",
            "topic_count": len(TOPICS),
            "paragraph_count": len(PARAGRAPHS)
        },
        "topics": TOPICS,
        "paragraphs": PARAGRAPHS
    }
    out_path = Path("docs/watch/research/embeddings/samples/quality_dataset.json")
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print(f"Saved dataset to {out_path} ({out_path.stat().st_size} bytes)")

    # Print summary statistics
    words = [len(p["text"].split()) for p in PARAGRAPHS]
    en_cnt = sum(1 for p in PARAGRAPHS if p["lang"] == "en")
    fr_cnt = sum(1 for p in PARAGRAPHS if p["lang"] == "fr")
    print(f"Paragraphs: {len(PARAGRAPHS)} total ({en_cnt} EN, {fr_cnt} FR)")
    print(f"Word counts: min={min(words)}, max={max(words)}, mean={sum(words)/len(words):.1f}")

if __name__ == "__main__":
    main()
