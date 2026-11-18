import '../models.dart';
import '../modules/modules.dart';

/// Jedno ćwiczenie w przewodniku treningowym.
class GuideExercise {
  final String id;
  final String title;
  final String goal;
  final List<String> steps;
  final String tip;
  const GuideExercise(this.id, this.title, this.goal, this.steps, this.tip);
}

/// Przewodnik treningowy dla jednego modułu.
class Guide {
  final AppModule module;
  final String intro;
  final List<String> statusLabels; // [nie zaczęte, w trakcie, opanowane]
  final Discipline? discipline; // dyscyplina do zapisu treningu
  final String? warning;
  final List<GuideExercise> exercises;
  const Guide(this.module, this.intro, this.exercises,
      {this.statusLabels = const ['Nie zaczęte', 'Ćwiczymy', 'Opanowane'], this.discipline, this.warning});
}

const guides = <AppModule, Guide>{
  AppModule.basicCommands: Guide(
    AppModule.basicCommands,
    'Krótkie sesje po 3–5 minut, kilka razy dziennie. Nagradzaj od razu (do 1 sekundy), kończ, zanim pies się znudzi.',
    discipline: Discipline.obedience,
    [
      GuideExercise('bc_name', 'Imię i kontakt', 'Pies patrzy na Ciebie, gdy słyszy imię.', [
        'W cichym pokoju powiedz imię psa raz, radośnie.',
        'Gdy spojrzy – od razu „tak!” i smakołyk.',
        'Powtórz 5–10 razy, potem w innych pokojach i na spacerze.',
      ], 'Nie powtarzaj imienia w kółko – mów je raz i czekaj.'),
      GuideExercise('bc_sit', 'Siad', 'Pies siada na jedno słowo, także na spacerze.', [
        'Trzymaj smakołyk przy nosie psa i powoli prowadź go nad głowę.',
        'Gdy pupa dotknie ziemi – nagroda.',
        'Po kilku powtórzeniach dodaj słowo „siad” tuż przed ruchem ręki.',
        'Stopniowo zmniejszaj gest, aż wystarczy samo słowo.',
      ], 'Nie dociskaj zadu ręką – pies ma sam zrozumieć, co się opłaca.'),
      GuideExercise('bc_down', 'Waruj', 'Pies kładzie się i czeka na zwolnienie.', [
        'Z pozycji siad prowadź smakołyk od nosa pionowo w dół, między łapy.',
        'Potem powoli wysuń rękę do przodu po podłodze.',
        'Gdy łokcie dotkną ziemi – nagroda między łapami.',
        'Dodaj słowo „waruj” i słowo zwalniające, np. „wolne”.',
      ], 'Na śliskiej podłodze ćwicz na macie lub dywanie.'),
      GuideExercise('bc_stay', 'Zostań', 'Pies zostaje w pozycji, gdy odchodzisz.', [
        'Pies w siadzie lub warowaniu. Powiedz „zostań”, zrób pół kroku w tył i od razu wróć.',
        'Nagroda, gdy wracasz do psa – nie wołaj go do siebie.',
        'Wydłużaj po kolei: czas, potem odległość, na końcu rozproszenia (zasada 3D).',
        'Zawsze kończ słowem zwalniającym.',
      ], 'Jeśli pies wstaje, cofnij się o krok trudności.'),
      GuideExercise('bc_heel', 'Chodzenie na luźnej smyczy', 'Smycz luźna, pies idzie obok.', [
        'Nagradzaj przy nodze co 2–3 kroki, gdy smycz jest luźna.',
        'Gdy smycz się napina – zatrzymaj się i stój jak drzewo.',
        'Ruszaj dopiero, gdy pies wróci i smycz się poluzuje.',
        'Wydłużaj odcinki między nagrodami.',
      ], 'Zacznij w domu i na podwórku, nie na pierwszym spacerze w parku.'),
      GuideExercise('bc_leave', 'Zostaw', 'Pies odpuszcza jedzenie lub przedmiot.', [
        'Zamknij smakołyk w pięści. Czekaj, aż pies przestanie go wąchać i lizać.',
        'Gdy odsunie nos – nagroda z drugiej ręki (nigdy tej „zakazanej”).',
        'Dodaj słowo „zostaw”, potem połóż smakołyk na podłodze i zasłaniaj stopą.',
      ], 'Bardzo przydaje się na spacerach przy jedzeniu z ziemi.'),
      GuideExercise('bc_place', 'Na miejsce', 'Pies idzie na posłanie i tam odpoczywa.', [
        'Rzuć smakołyk na posłanie, nagroda gdy na nie wejdzie.',
        'Dodaj słowo „miejsce” i nagradzaj warowanie na posłaniu.',
        'Wydłużaj czas leżenia, nagradzając spokojnie, co jakiś czas.',
      ], 'Pomaga, gdy przychodzą goście albo przy jedzeniu.'),
    ],
  ),
  AppModule.recall: Guide(
    AppModule.recall,
    'Przywołanie budujemy etapami: od łatwych miejsc do trudnych. Na każde przyjście – najlepsza nagroda. Nigdy nie karz psa, który przyszedł.',
    [
      GuideExercise('rc_home', '1. Gra w domu', 'Pies biegnie na słowo „do mnie”.', [
        'Dwie osoby w różnych pokojach na zmianę wołają psa.',
        'Przy każdym przyjściu: dotknij obroży i daj nagrodę.',
        'Wołaj tylko raz, radosnym głosem.',
      ], 'Dotykanie obroży uczy, że przyjście nie kończy zabawy.'),
      GuideExercise('rc_yard', '2. Podwórko / ogród', 'Przywołanie przy małych rozproszeniach.', [
        'Wołaj, gdy pies nie jest bardzo zajęty (np. kończy wąchać).',
        'Nagroda jackpot: kilka smakołyków po kolei.',
        'Po nagrodzie często puść psa z powrotem do zabawy.',
      ], 'Wołaj tylko wtedy, gdy masz pewność, że przyjdzie.'),
      GuideExercise('rc_line', '3. Linka 10 m', 'Bezpieczny trening w nowych miejscach.', [
        'Linka przypięta do szelek, nie do obroży.',
        'Zawołaj raz. Jeśli nie reaguje – zachęć gestem, kucnij, odejdź.',
        'Nie ciągnij psa linką do siebie – ona tylko zabezpiecza.',
      ], 'Używaj rękawiczek, żeby linka nie poparzyła dłoni.'),
      GuideExercise('rc_distraction', '4. Rozproszenia', 'Pies przychodzi mimo innych psów, ludzi, zapachów.', [
        'Zacznij od dużej odległości od rozproszenia.',
        'Z każdym sukcesem podejdź trochę bliżej.',
        'Na najtrudniejsze sytuacje miej najlepsze nagrody (np. mięso, szarpak).',
      ], 'Jeśli się nie uda, zwiększ odległość i ćwicz dalej.'),
      GuideExercise('rc_whistle', '5. Gwizdek', 'Sygnał słyszalny z daleka i zawsze taki sam.', [
        'Gwizdnij i od razu daj wyjątkowy smakołyk – bez żadnych wymagań (10×/dzień przez tydzień).',
        'Potem gwiżdż, gdy pies jest blisko i patrzy na Ciebie.',
        'Stopniowo przenieś do trudniejszych miejsc, jak przy słowie.',
      ], 'Gwizdek nie zdradza emocji – nawet gdy jesteś zdenerwowany.'),
      GuideExercise('rc_emergency', '6. Przywołanie awaryjne', 'Specjalne słowo na sytuacje zagrożenia.', [
        'Wybierz słowo, którego nie używasz na co dzień (np. „pizza!”).',
        'Używaj rzadko, zawsze z największą nagrodą (cała garść).',
        'Ćwicz maksymalnie raz–dwa razy w tygodniu.',
      ], 'To słowo nigdy nie może kojarzyć się z końcem zabawy.'),
      GuideExercise('rc_free', '7. Bez linki', 'Pewne przywołanie w bezpiecznym, ogrodzonym terenie.', [
        'Zacznij od ogrodzonego wybiegu w spokojnej porze.',
        'Przywołuj w różnych momentach, często puszczając dalej.',
        'Wracaj do linki, jeśli skuteczność spadnie poniżej 9 na 10.',
      ], 'Przestrzegaj przepisów o psach bez smyczy w Twojej okolicy.'),
    ],
  ),
  AppModule.socialization: Guide(
    AppModule.socialization,
    'Szczenię najłatwiej oswaja świat do ok. 16. tygodnia życia, ale dorosły pies też się uczy. Pokazuj nowe rzeczy z dystansu, krótko i z nagrodą. Pies może zawsze się wycofać.',
    statusLabels: ['Do poznania', 'Oswajamy', 'Bez stresu'],
    [
      GuideExercise('so_people', 'Różni ludzie', 'Spokój przy obcych osobach.', [
        'Dzieci, starsze osoby, ludzie w kapeluszach, z laską, parasolem, w kapturze.',
        'Pozwól psu obserwować z odległości i nagradzaj spokój.',
        'Nie zmuszaj do głaskania – pies sam decyduje, czy podejść.',
      ], 'Poproś obcych, by nie pochylali się nad psem.'),
      GuideExercise('so_dogs', 'Inne psy', 'Uprzejme spotkania z innymi psami.', [
        'Wybieraj spokojne, zrównoważone psy znajomych.',
        'Krótkie powitania (3 sekundy), potem odwołaj i nagródź.',
        'Unikaj przypadkowych psów na smyczy i zatłoczonych wybiegów.',
      ], 'Jedno złe doświadczenie potrafi zostać na długo.'),
      GuideExercise('so_sounds', 'Dźwięki', 'Brak lęku przed hałasem.', [
        'Odtwarzaj nagrania: burza, fajerwerki, odkurzacz, dzwonek, płacz dziecka.',
        'Zacznij bardzo cicho podczas jedzenia lub zabawy.',
        'Przez kolejne dni stopniowo zwiększaj głośność.',
      ], 'Przed Sylwestrem zacznij ćwiczyć z kilkutygodniowym wyprzedzeniem.'),
      GuideExercise('so_surfaces', 'Podłoża', 'Pewne chodzenie po różnych nawierzchniach.', [
        'Kratki, metal, śliskie płytki, schody, kładki, piasek, woda.',
        'Rozrzuć smakołyki na nowym podłożu i pozwól psu badać.',
        'Nie wciągaj psa na siłę – zachęcaj.',
      ], 'Przydaje się później w agility i na wystawach.'),
      GuideExercise('so_transport', 'Transport', 'Spokojne podróże.', [
        'Najpierw siedzenie w stojącym aucie z gryzakiem.',
        'Potem krótkie przejazdy (5 min) zakończone czymś przyjemnym.',
        'Autobus, tramwaj, pociąg – najpierw poza godzinami szczytu.',
      ], 'Psa wieź w klatce lub zapiętego w szelkach.'),
      GuideExercise('so_city', 'Miasto', 'Spokój przy ruchu ulicznym.', [
        'Usiądź na ławce z dala od ulicy i nagradzaj spokojne obserwowanie.',
        'Rowery, hulajnogi, wózki, tramwaje – stopniowo bliżej.',
        'Krótkie wizyty w sklepach zoologicznych przyjaznych psom.',
      ], 'Po wizycie w mieście daj psu odpocząć – to dużo wrażeń.'),
      GuideExercise('so_handling', 'Dotyk i pielęgnacja', 'Pies pozwala dotykać łap, uszu, zębów.', [
        'Dotknij łapy – smakołyk. Powtarzaj codziennie po kilka razy.',
        'Dołóż: zaglądanie w uszy, do pyska, czesanie, obcinanie pazurów (po jednym).',
        'Odwiedzaj gabinet weterynarza „towarzysko” – tylko po smakołyk.',
      ], 'Na wystawach i u weterynarza to ogromne ułatwienie.'),
      GuideExercise('so_alone', 'Zostawanie samemu', 'Pies spokojnie czeka w domu.', [
        'Zacznij od wyjścia do innego pokoju na kilka sekund.',
        'Potem krótkie wyjścia za drzwi, bez pożegnań i powitań.',
        'Daj psu gryzak lub matę węchową na czas wyjścia.',
      ], 'Wydłużaj czas powoli – lepiej za wolno niż za szybko.'),
    ],
  ),
  AppModule.mindGames: Guide(
    AppModule.mindGames,
    '15 minut pracy nosem i głową zmęczy psa jak długi spacer. Dobre na deszczowe dni, po zabiegach i dla psów, które nie mogą dużo biegać.',
    [
      GuideExercise('mg_grass', 'Szukanie w trawie', 'Węszenie rozładowuje stres i męczy.', [
        'Rozsyp garść karmy w trawie na powierzchni ok. 2×2 m.',
        'Powiedz „szukaj” i pozwól psu wyjadać.',
        'Z czasem zwiększaj obszar i wysokość trawy.',
      ], 'Świetne na koniec spaceru albo po treningu.'),
      GuideExercise('mg_mat', 'Mata węchowa', 'Spokojne jedzenie z pracą nosa.', [
        'Wsyp część posiłku w matę węchową.',
        'Zacznij od łatwego wkładania na wierzch, potem głębiej.',
        'Pilnuj, żeby pies nie gryzł maty.',
      ], 'Matę można zrobić samemu z gumowej maty i pasków polaru.'),
      GuideExercise('mg_cups', 'Gra w kubki', 'Wskazywanie właściwego kubka.', [
        'Pod jednym z 3 kubków schowaj smakołyk na oczach psa.',
        'Nagradzaj, gdy pies wskaże dobry kubek nosem lub łapą.',
        'Potem przesuwaj kubki, gdy pies patrzy.',
      ], 'Używaj plastikowych kubków – nie potłuką się.'),
      GuideExercise('mg_toy', 'Szukaj zabawki', 'Odnajdywanie ulubionej zabawki po nazwie.', [
        'Schowaj zabawkę w łatwym miejscu, gdy pies widzi.',
        'Powiedz „szukaj piłki” i pochwal za znalezienie.',
        'Potem chowaj w innym pokoju, gdy pies czeka.',
      ], 'Niektóre psy uczą się nazw kilkunastu zabawek.'),
      GuideExercise('mg_kong', 'Mrożony Kong', 'Długie, spokojne zajęcie.', [
        'Napełnij Konga mokrą karmą lub namoczoną suchą karmą.',
        'Zamroź na kilka godzin.',
        'Podaj w miejscu, gdzie pies może spokojnie lizać.',
      ], 'Wlicz to do dziennej porcji jedzenia.'),
      GuideExercise('mg_box', 'Zabawa z pudełkiem', 'Pies sam proponuje zachowania (shaping).', [
        'Połóż na podłodze karton. Nagradzaj każde zainteresowanie: spojrzenie, krok, dotyk.',
        'Potem nagradzaj tylko więcej: łapa w pudle, dwie łapy, wejście.',
        'Sesja 3–5 minut, kończ sukcesem.',
      ], 'Najlepiej z klikerem – oznacza dokładny moment.'),
      GuideExercise('mg_tricks', 'Sztuczki', 'Daj łapę, obrót, ukłon, cofanie.', [
        'Uczysz jak komend: wabik smakołykiem, nagroda, potem słowo.',
        'Jedna nowa sztuczka na raz.',
        'Sztuczki rozciągają mięśnie – ukłon to świetna rozgrzewka.',
      ], 'Krótko i wesoło – to ma być zabawa.'),
    ],
  ),
  AppModule.agility: Guide(
    AppModule.agility,
    'Agility to tor przeszkód pokonywany na czas. Zaczynamy od podstaw prowadzenia i niskich przeszkód. Pełne skoki dopiero po zakończeniu wzrostu (12–18 mies. zależnie od rasy).',
    discipline: Discipline.condition,
    [
      GuideExercise('ag_handling', 'Prowadzenie po obu stronach', 'Pies biegnie przy lewej i prawej nodze.', [
        'Nagradzaj psa biegnącego obok, po jednej stronie, potem po drugiej.',
        'Ćwicz zmiany kierunku: pies podąża za Twoim ramieniem.',
        'Ucz komend „prawo / lewo” lub „hop / tunel” od pierwszych sesji.',
      ], 'Twoje ciało jest najważniejszym sygnałem dla psa.'),
      GuideExercise('ag_jump', 'Skok przez stacjonatę', 'Prawidłowy, spokojny skok.', [
        'Zacznij od drążka na ziemi – pies tylko przechodzi.',
        'Podnoś stopniowo: kilka cm co sesję.',
        'Rzucaj nagrodę za przeszkodę, żeby pies patrzył przed siebie.',
      ], 'Młody pies – drążek najwyżej na wysokość nadgarstka.'),
      GuideExercise('ag_tunnel', 'Tunel', 'Pies chętnie wbiega w tunel.', [
        'Skróć tunel do minimum, druga osoba trzyma psa.',
        'Zawołaj psa z drugiego końca, nagroda na wyjściu.',
        'Wydłużaj tunel i dodawaj łuk.',
      ], 'Większość psów kocha tunel – dobra nagroda na koniec.'),
      GuideExercise('ag_weave', 'Slalom', 'Wejście w slalom i rytm.', [
        'Zacznij od 2 tyczek (metoda 2×2): pies przechodzi między nimi.',
        'Dodawaj kolejne pary i zmieniaj kąt wejścia.',
        'Zawsze wejście z prawym barkiem psa przy pierwszej tyczce.',
      ], 'To najtrudniejsza przeszkoda – potrzebuje miesięcy.'),
      GuideExercise('ag_contact', 'Strefy kontaktowe', 'Pies dotyka strefy na kładce, A-ramie, huśtawce.', [
        'Naucz pozycji na końcu deski: 2 łapy na desce, 2 na ziemi.',
        'Najpierw na niskiej desce na ziemi, potem na przeszkodzie.',
        'Nagradzaj w pozycji, zwalniaj słowem.',
      ], 'Wysokie przeszkody kontaktowe dopiero u dorosłego psa.'),
      GuideExercise('ag_teeter', 'Huśtawka', 'Pies nie boi się ruchu i hałasu deski.', [
        'Najpierw obniż huśtawkę lub trzymaj ją ręką.',
        'Pozwól psu wejść kawałek i wrócić – nagradzaj odwagę.',
        'Stopniowo pozwól, by deska opadała sama.',
      ], 'Jedna zła przygoda z huśtawką = długie odkręcanie strachu.'),
      GuideExercise('ag_start', 'Pozycja startowa', 'Pies czeka na starcie, aż go zwolnisz.', [
        'Pies siedzi przed pierwszą przeszkodą.',
        'Odchodzisz 1–2 kroki, wracasz i nagradzasz.',
        'Zwiększaj odległość, startuj dopiero na komendę.',
      ], 'Dobry start oszczędza sekundy na zawodach.'),
    ],
  ),
  AppModule.dogtrekking: Guide(
    AppModule.dogtrekking,
    'Dogtrekking to wędrówka z psem w szelkach po wyznaczonej trasie – od kilkunastu do 100+ km. Klucz to stopniowe budowanie dystansu i dbanie o łapy.',
    discipline: Discipline.walk,
    [
      GuideExercise('dt_gear', 'Sprzęt', 'Wygodne szelki i linka z amortyzatorem.', [
        'Szelki trekkingowe (nie ograniczające ruchu barków).',
        'Linka z amortyzatorem i pas biodrowy dla człowieka.',
        'Woda, miska, apteczka, buty dla psa, czołówka.',
      ], 'Sprzęt zapisz w module Sprzęt – policzę zużycie po kilometrach.'),
      GuideExercise('dt_commands', 'Komendy kierunkowe', 'Prawo, lewo, prosto, stój, wolno.', [
        'Na spacerach mów „prawo/lewo” przy każdym skręcie i nagradzaj.',
        'Ucz „stój” – przydatne przy przejściach i zejściach.',
        'Ucz „wolno” przed stromymi zejściami.',
      ], 'Te same komendy przydadzą się w canicrossie.'),
      GuideExercise('dt_distance', 'Budowanie dystansu', 'Bezpieczne zwiększanie kilometrów.', [
        'Zwiększaj tygodniowy dystans maksymalnie o ok. 10%.',
        'Co 3–4 tygodnie lżejszy tydzień.',
        'Długie trasy tylko z dorosłym, zdrowym psem.',
      ], 'Dystans tygodniowy widzisz w Statystykach.'),
      GuideExercise('dt_terrain', 'Teren i przewyższenia', 'Pies radzi sobie w górach i lesie.', [
        'Zacznij od pagórków, potem dłuższe podejścia.',
        'Na zejściach zwolnij – obciążają stawy psa.',
        'Nagrywaj trasy GPS, żeby widzieć przewyższenia.',
      ], 'Unikaj ostrych kamieni i rozgrzanego asfaltu.'),
      GuideExercise('dt_food', 'Picie i jedzenie na trasie', 'Energia na długie kilometry.', [
        'Pój psa co 30–60 min, w upał częściej.',
        'Na trasach ponad 20 km małe przekąski co 1–2 h.',
        'Duży posiłek dopiero 1–2 h po zakończeniu.',
      ], 'Nie karm psa dużą porcją tuż przed startem.'),
      GuideExercise('dt_paws', 'Łapy', 'Zdrowe opuszki po długiej trasie.', [
        'Przed trasą: maść ochronna na opuszki.',
        'Co postój sprawdź łapy – kamyki, otarcia, kleszcze.',
        'Na żwir i śnieg – buty dla psa (przyzwyczajaj wcześniej).',
      ], 'Po trasie sprawdź też pachy i pachwiny pod szelkami.'),
      GuideExercise('dt_recovery', 'Regeneracja', 'Odpoczynek po wysiłku.', [
        'Po długiej trasie dzień lub dwa spokojnych spacerów.',
        'Masaż, ciepłe miejsce do spania.',
        'Obserwuj kulawiznę i sztywność – w razie wątpliwości weterynarz.',
      ], 'Wpisz dzień regeneracji w planie treningów.'),
    ],
  ),
  AppModule.protection: Guide(
    AppModule.protection,
    'Obrona (dział C w IGP) to sport, nie szkolenie psa do atakowania ludzi. Ćwicz wyłącznie w klubie, pod okiem doświadczonego pozoranta i instruktora.',
    discipline: Discipline.igp,
    warning: 'Nie ćwicz obrony samodzielnie. Do egzaminu IGP pies musi mieć zdany BH-VT.',
    [
      GuideExercise('pr_drive', 'Zabawa i popęd', 'Pies chętnie walczy o szarpak.', [
        'Zabawa szarpakiem z przewodnikiem – krótko i intensywnie.',
        'Pies „wygrywa” zdobycz i nosi ją z dumą.',
        'Budowanie pewności siebie przed pracą z pozorantem.',
      ], 'Pies ma się bawić, nie bać.'),
      GuideExercise('pr_grip', 'Pełny, spokojny chwyt', 'Chwyt całym pyskiem, bez przechwytywania.', [
        'Pozorant prezentuje szarpak/rękaw tak, by ułatwić pełny chwyt.',
        'Nagrodą jest wygrana zdobycz.',
        'Pozorant stopniowo dodaje lekki nacisk i ruch.',
      ], 'Jakość chwytu buduje się latami – bez pośpiechu.'),
      GuideExercise('pr_out', 'Puść (aus)', 'Pies puszcza na komendę i pilnuje.', [
        'Pozorant zamiera, zdobycz staje się „martwa”.',
        'Przewodnik mówi „puść”, nagroda: ponowny chwyt.',
        'Z czasem pies pilnuje pozoranta po puszczeniu.',
      ], 'Bez czystego „puść” nie ma bezpiecznej obrony.'),
      GuideExercise('pr_hold', 'Oszczekiwanie w kryjówce', 'Pies oszczekuje pozoranta, nie dotykając go.', [
        'Pozorant w kryjówce, pies na smyczy przed nim.',
        'Nagroda (chwyt) za ciągłe, pewne szczekanie.',
        'Wydłużaj czas oszczekiwania.',
      ], 'Ćwiczenie z działu C na egzaminie.'),
      GuideExercise('pr_transport', 'Przeprowadzenie', 'Pies idzie spokojnie przy nodze za pozorantem.', [
        'Najpierw przeprowadzenie bez pozoranta, jak chodzenie przy nodze.',
        'Potem za pozorantem w dużej odległości.',
        'Nagradzaj skupienie i spokój.',
      ], 'Kontrola jest tak samo ważna jak chwyt.'),
      GuideExercise('pr_attack', 'Atak z ruchu', 'Pewny chwyt w ruchu – tylko u przygotowanego psa.', [
        'Wyłącznie po opanowaniu chwytu i „puść”.',
        'Pozorant ustala odległość i tempo.',
        'Kończ po udanym powtórzeniu.',
      ], 'Decyzję o kolejnych krokach podejmuje instruktor.'),
    ],
  ),
};
