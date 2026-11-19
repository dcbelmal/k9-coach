// Tłumaczenia (en) tekstów z korekty merytorycznej 0.15. Klucz = tekst polski.
// Osobny plik, żeby nie kolidować z równoległymi zmianami w en.dart.
// ignore_for_file: lines_longer_than_80_chars
const strings = <String, String>{
  // --- Żywienie ---
  ' Masę docelową oszacowałem z BCS – wpisz ją w profilu.':
      ' I estimated the target weight from BCS – enter it in the profile.',
  'Bieg z dystansem dziś: +{0} kcal ponad zwykłą aktywność.': 'Distance run today: +{0} kcal above normal activity.',
  'Budowa masy: +10% do zapotrzebowania (wpisz masę docelową, by liczyć dokładniej).':
      'Weight gain: +10% to requirement (enter a target weight for a more accurate calculation).',
  'Budowa masy: liczę utrzymanie masy docelowej ({0} kg), stopniowo.':
      'Weight gain: I calculate maintenance of the target weight ({0} kg), gradually.',
  'Cel na dziś (orientacyjnie)': 'Today\'s goal (approximate)',
  'Dodatkowy wysiłek (bieg z dystansem)': 'Extra effort (distance run)',
  'Dużo swobodnego biegania lub codzienna praca (poza zapisanymi treningami)':
      'Lots of free running or daily work (outside logged trainings)',
  'Karma główna da mniej niż 80% energii na utrzymanie. Przy takim ograniczeniu zwykła karma może nie pokryć białka, witamin i minerałów – rozważ karmę dietetyczną i skonsultuj plan z lekarzem weterynarii.': 'The main food will provide less than 80% of maintenance energy. With such a restriction a regular food may not cover protein, vitamins and minerals – consider a weight-loss diet and discuss the plan with your vet.',
  'Korekta zatwierdzona przez Ciebie: {0}{1}%.': 'Adjustment you approved: {0}{1}%.',
  'Redukcja: 1,0 × RER masy docelowej ({0} kg).': 'Weight loss: 1.0 × RER of the target weight ({0} kg).',
  'Redukcja: wpisz masę docelową w profilu (albo BCS), a policzę dawkę od masy idealnej.':
      'Weight loss: enter a target weight (or BCS) in the profile and I\'ll calculate from the ideal weight.',
  'Senior: zapotrzebowanie bywa niższe albo wyższe niż u dorosłego – kieruj się masą i BCS.':
      'Senior: energy needs may be lower or higher than in adults – follow body weight and BCS.',
  'Typowy zakres dla psa o tych danych': 'Typical range for a dog with these data',
  'U rosnącego psa nie liczę redukcji ani budowy masy – zmianę dawki ustal z lekarzem weterynarii.':
      'For a growing dog I don\'t calculate weight loss or gain – agree any change with your vet.',
  'Wzory: RER = 70 × masa^0,75, mnożniki wg NRC 2006 i WSAVA/AAHA. Psy o tej samej masie potrzebują nawet o 20% mniej lub więcej – to punkt startowy, nie dawka ustalona dla Twojego psa. Koryguj co 2–3 tygodnie wg masy i BCS, a przy chorobie, ciąży, laktacji lub silnej redukcji ustal dietę z lekarzem weterynarii.': 'Formulas: RER = 70 × weight^0.75, factors per NRC 2006 and WSAVA/AAHA. Dogs of the same weight may need up to 20% less or more – this is a starting point, not a dose set for your dog. Adjust every 2–3 weeks based on weight and BCS; in illness, pregnancy, lactation or strong weight loss plan the diet with your vet.',
  'Zapotrzebowanie bazowe': 'Base requirement',
  'cel ok. {0} (bieg +{1})': 'goal approx. {0} (run +{1})',
  'cel ok. {0} kcal': 'goal approx. {0} kcal',
  '{0}{1} · w zapotrzebowaniu bazowym': '{0}{1} · included in base requirement',
  '{0}–{1} kcal': '{0}–{1} kcal',
  'Za mało ważeń na ocenę trendu': 'Not enough weigh-ins to assess the trend',
  'Do oceny zmiany dawki potrzebuję co najmniej 3 ważeń z okresu min. 3 tygodni. Krótkie wahania (woda, jelita, pora dnia) nie są podstawą do zmiany porcji.': 'To judge a portion change I need at least 3 weigh-ins over at least 3 weeks. Short fluctuations (water, gut content, time of day) are no reason to change the portion.',
  'Cel osiągnięty': 'Goal reached',
  'Pies osiągnął wagę docelową. Zmień cel na „Utrzymanie wagi”.':
      'The dog has reached the target weight. Change the goal to “Maintain weight”.',
  'Redukcja stoi w miejscu': 'Weight loss has stalled',
  'Przez ostatnie tygodnie waga zmienia się o {0}% tygodniowo (zalecane ok. 1–2%). Najpierw sprawdź, czy wszystkie przysmaki są zapisane. Możesz zmniejszyć dawkę o 5% i ocenić efekt po 2–3 tygodniach.': 'Over the last weeks weight changes by {0}% per week (recommended approx. 1–2%). First check that all treats are logged. You can reduce the portion by 5% and review after 2–3 weeks.',
  'Za szybkie chudnięcie': 'Losing weight too fast',
  'Spadek {0}% tygodniowo to więcej niż zalecane 1–2%. Proponuję zwiększyć dawkę o 5%. Jeśli pies chudnie mimo jedzenia – skontaktuj się z lekarzem weterynarii.': 'A loss of {0}% per week is more than the recommended 1–2%. I suggest increasing the portion by 5%. If the dog keeps losing weight despite eating – contact your vet.',
  'Redukcja idzie dobrze': 'Weight loss on track',
  'Spadek {0}% tygodniowo – bezpieczne tempo. Bez zmian.': '{0}% loss per week – a safe pace. No change.',
  'Masa docelowa osiągnięta': 'Target weight reached',
  'Zmień cel na „Utrzymanie wagi”, żeby pies nie przybierał dalej.':
      'Change the goal to “Maintain weight” so the dog doesn\'t keep gaining.',
  'Masa nie rośnie': 'Weight is not increasing',
  'Przyrost {0}% tygodniowo. Możesz zwiększyć dawkę o 5% i ocenić efekt po 2–3 tygodniach. Niezamierzona utrata masy wymaga wizyty u lekarza weterynarii.': 'Gain {0}% per week. You can increase the portion by 5% and review after 2–3 weeks. Unintended weight loss needs a vet visit.',
  'Szybki przyrost': 'Fast gain',
  'Waga rośnie o {0}% tygodniowo. Sprawdź kondycję (BCS) – może wystarczy −5%.':
      'Weight rises by {0}% per week. Check body condition (BCS) – maybe −5% is enough.',
  'Budowa masy w normie': 'Weight gain on track',
  'Tempo przyrostu jest właściwe. Bez zmian.': 'The rate of gain is right. No change.',
  'Waga rośnie': 'Weight is rising',
  'Trend z ostatnich tygodni: +{0}% tygodniowo. Jeśli BCS też rośnie, możesz zmniejszyć dawkę o 5%.':
      'Trend over recent weeks: +{0}% per week. If BCS is rising too, you can reduce the portion by 5%.',
  'Waga spada': 'Weight is falling',
  'Trend z ostatnich tygodni: {0}% tygodniowo. Możesz zwiększyć dawkę o 5%. Niewyjaśniony spadek masy skonsultuj z lekarzem weterynarii.': 'Trend over recent weeks: {0}% per week. You can increase the portion by 5%. Discuss unexplained weight loss with your vet.',
  'Ten tydzień jest cięższy niż zwykle. Do dawki doliczam tylko bieg z dystansem{0} – zwykła aktywność jest już w zapotrzebowaniu bazowym. Pilnuj wody i regeneracji.': 'This week is harder than usual. I only add distance runs to the portion{0} – normal activity is already in the base requirement. Watch water and recovery.',

  // --- Cieczka ---
  'Krwawienie': 'Bleeding',
  'Obrzęk sromu': 'Vulvar swelling',
  'Jaśniejsza wydzielina': 'Lighter discharge',
  'Przyjmuje psa / odstawia ogon': 'Accepts the male / flags tail',
  'Częste znaczenie moczem': 'Frequent urine marking',
  'Zmiana zachowania': 'Behaviour change',
  'Progesteron': 'Progesterone',
  'Cytologia': 'Cytology',
  'obraz proestrus': 'proestrus picture',
  'obraz estrus': 'estrus picture',
  'obraz diestrus': 'diestrus picture',
  'inny / niejednoznaczny': 'other / inconclusive',
  'poziom podstawowy – zwykle przed owulacją': 'baseline level – usually before ovulation',
  'wzrost – zwykle okolice piku LH': 'rising – usually around the LH peak',
  'zakres typowy dla okolic owulacji': 'range typical around ovulation',
  'wysoki – zwykle po owulacji': 'high – usually after ovulation',
  'Proestrus (początek cieczki)': 'Proestrus (start of heat)',
  'Krwawienie i obrzęk sromu. Suka zwykle przyciąga psy, ale ich nie przyjmuje. Trwa średnio ok. 9 dni (zwykle 3–17).': 'Bleeding and vulvar swelling. The bitch usually attracts males but doesn\'t accept them. Lasts about 9 days on average (usually 3–17).',
  'Estrus (ruja)': 'Estrus (standing heat)',
  'Suka przyjmuje psa, wydzielina często jaśnieje. W tej fazie dochodzi do owulacji. Moment płodny wyznacza lekarz na podstawie badań.': 'The bitch accepts the male, discharge often gets lighter. Ovulation happens in this phase. The fertile moment is determined by the vet based on tests.',
  'Cieczka trwa': 'In heat',
  'Proestrus i estrus trudno rozróżnić bez badań. Suka może być płodna przez całą cieczkę – pilnuj jej na spacerach.': 'Proestrus and estrus are hard to tell apart without tests. The bitch may be fertile throughout the heat – watch her on walks.',
  'Diestrus (po cieczce)': 'Diestrus (after heat)',
  'Ok. 2 miesięcy po rui (szacunkowo). Możliwa ciąża urojona: obserwuj apetyt, sutki i zachowanie.':
      'About 2 months after estrus (estimate). False pregnancy is possible: watch appetite, teats and behaviour.',
  'Anestrus (spoczynek)': 'Anestrus (rest)',
  'Okres bez cieczki (szacunkowo). Każda suka ma własny rytm – obserwuj pierwsze objawy kolejnej cieczki.':
      'Period without heat (estimate). Every bitch has her own rhythm – watch for the first signs of the next heat.',
  'Zapisz początek cieczki, a pokażę orientacyjny etap cyklu i kolejny termin.':
      'Log the start of heat and I\'ll show the approximate cycle stage and the next date.',
  'szacunkowo ±{0} dni': 'estimate ±{0} days',
  'średnia z Twoich wpisów ({0})': 'average of your entries ({0})',
  'bez historii przyjmuję ok. 6 miesięcy – u suk zwykle 5–12 mies.':
      'without history I assume about 6 months – bitches usually 5–12 months',
  'Tydzień przed i w dniu orientacyjnego terminu, a w trakcie cieczki – przypomnienie o badaniach i zapisie końca':
      'A week before and on the estimated date; during heat – reminders about tests and logging the end',
  'Prognozy są szacunkowe. Kalendarz nie wyznacza dni płodnych ani „bezpiecznych” dni – suka może zajść w ciążę w różnych dniach cieczki. Moment krycia ustala lekarz weterynarii na podstawie progesteronu i cytologii.': 'Forecasts are estimates. A calendar cannot determine fertile or “safe” days – a bitch can conceive on different days of heat. The vet sets the mating time based on progesterone and cytology.',
  'Faza wg owulacji potwierdzonej przez lekarza.': 'Phase based on vet-confirmed ovulation.',
  'Faza wg ostatniej cytologii.': 'Phase based on the latest cytology.',
  'Faza wg Twojej obserwacji (suka przyjmuje psa) – szacunkowo.':
      'Phase based on your observation (accepts the male) – estimate.',
  'Szacunek z kalendarza – bez badań faza jest niepewna.': 'Calendar estimate – without tests the phase is uncertain.',
  'Owulacja (wg lekarza): {0}. Największa płodność zwykle do ok. {1} – termin krycia ustal z lekarzem.':
      'Ovulation (per vet): {0}. Peak fertility usually until about {1} – agree the mating date with your vet.',
  'Kolejna cieczka orientacyjnie {0} ({1})': 'Next heat approx. {0} ({1})',
  'owulacja {0}': 'ovulation {0}',
  'badania: {0}': 'tests: {0}',
  'Objawy': 'Signs',
  'Suka przyjmuje psa od (opcjonalnie)': 'Accepts the male from (optional)',
  'Owulacja potwierdzona przez lekarza (opcjonalnie)': 'Ovulation confirmed by vet (optional)',
  'Badania': 'Tests',
  'Brak badań. Wyniki wpisuj z datą pobrania – tak jak podało laboratorium.':
      'No tests. Enter results with the sampling date – exactly as the lab reported.',
  'Progesteron {0} {1}': 'Progesterone {0} {1}',
  'Cytologia: {0}': 'Cytology: {0}',
  'Opis poziomu progesteronu jest orientacyjny (wg literatury). Laboratoria mają różne normy – wynik i dzień krycia interpretuje lekarz weterynarii.': 'The progesterone description is approximate (from literature). Labs use different ranges – the vet interprets the result and the mating day.',
  'Data owulacji musi przypadać w trakcie tej cieczki': 'The ovulation date must fall within this heat',
  'Data pobrania': 'Sampling date',
  'Wynik': 'Result',
  'Opis lekarza': 'Vet\'s description',
  'Notatki (laboratorium, lekarz)': 'Notes (lab, vet)',
  'Wpisz poprawny wynik': 'Enter a valid result',
  'Wybierz opis wyniku': 'Choose a result description',
  'Cieczka: planujesz krycie?': 'Heat: planning a mating?',
  '{0}: jeśli planujesz krycie, ustal z lekarzem weterynarii termin badania progesteronu. Suka może być płodna przez całą cieczkę – pilnuj jej na spacerach.': '{0}: if you plan a mating, agree a progesterone test date with your vet. The bitch may be fertile throughout the heat – watch her on walks.',

  // --- Ciąża i mioty ---
  'Krycie': 'Mating',
  'Zwykła codzienna aktywność jest w porządku. Unikaj przegrzania, bardzo forsownego wysiłku i zawodów, a plan treningów omów z lekarzem weterynarii.': 'Normal daily activity is fine. Avoid overheating, very strenuous effort and competitions, and discuss the training plan with your vet.',
  'Ok. 17.–21. dnia od owulacji zarodki zagnieżdżają się w macicy. Zwykła dieta i umiarkowany ruch.':
      'Around days 17–21 after ovulation the embryos implant. Normal diet and moderate exercise.',
  'Od ok. 25. dnia od owulacji (po samym kryciu zwykle od 28.–30. dnia) lekarz może potwierdzić ciążę w USG. USG nie służy do dokładnego liczenia szczeniąt.': 'From about day 25 after ovulation (from mating usually day 28–30) the vet can confirm pregnancy by ultrasound. Ultrasound is not for counting puppies accurately.',
  'Więcej energii w diecie': 'More energy in the diet',
  'W drugiej połowie ciąży zapotrzebowanie rośnie stopniowo. Ilość karmy zwiększaj wg masy i kondycji suki oraz zaleceń lekarza – zwykle o 25–50% pod koniec ciąży, zależnie od liczby szczeniąt. Najczęściej poleca się karmę dla szczeniąt lub ciężarnych suk.': 'In the second half of pregnancy needs rise gradually. Increase food according to the bitch\'s weight, condition and your vet\'s advice – usually by 25–50% by the end, depending on litter size. A puppy or pregnancy food is usually recommended.',
  'Szkielety szczeniąt są widoczne w RTG od ok. 45. dnia, a najdokładniej liczy się je zwykle po 55. dniu. O badaniu decyduje lekarz.': 'Puppy skeletons are visible on X-ray from about day 45; counting is most accurate after day 55. The vet decides on the exam.',
  'Spokojniejszy ruch': 'Calmer exercise',
  'Pod koniec ciąży krótsze, spokojne spacery. Bez skoków, ciągnięcia i biegu przy rowerze.':
      'Late in pregnancy shorter, calm walks. No jumping, pulling or running next to a bike.',
  'Przygotuj kojec w cichym, ciepłym miejscu. Niech suka się do niego przyzwyczai. Ustal z lekarzem, jak się kontaktować w razie porodu.': 'Prepare a whelping box in a quiet, warm place and let the bitch get used to it. Agree with your vet how to reach them during whelping.',
  'Mierz temperaturę 2 razy dziennie o stałych porach. Spadek (często poniżej ok. 37,5 °C) zwykle poprzedza poród o 12–24 h, ale nie u każdej suki – to nie jest pewny znak porodu.': 'Take her temperature twice a day at fixed times. A drop (often below about 37.5 °C) usually precedes whelping by 12–24 h, but not in every bitch – it is not a certain sign.',
  'Termin orientacyjny. Sprawdź okno porodu powyżej – jeśli zostanie przekroczone, skontaktuj się z lekarzem.':
      'Approximate date. Check the whelping window above – if it is exceeded, contact your vet.',
  'Zielona lub czarna wydzielina przed urodzeniem pierwszego szczenięcia':
      'Green or black discharge before the first puppy is born',
  'Silne parcie przez 20–30 minut bez urodzenia szczenięcia': 'Strong straining for 20–30 minutes without a puppy',
  'Ponad 2 godziny przerwy między szczeniętami, gdy w macicy są kolejne':
      'More than 2 hours between puppies while more remain',
  'Ponad 24 godziny od spadku temperatury bez akcji porodowej':
      'More than 24 hours after the temperature drop without labour',
  'Obfite krwawienie, gorączka, apatia, wymioty lub odmowa jedzenia':
      'Heavy bleeding, fever, lethargy, vomiting or refusing food',
  'Drżenia, niepokój, sztywność mięśni w ciąży lub karmieniu (możliwa tężyczka)':
      'Trembling, restlessness, muscle stiffness in pregnancy or lactation (possible eclampsia)',
  'Termin porodu przekroczony (ponad 64–66 dni od owulacji lub 72 dni od krycia)':
      'Due date exceeded (over 64–66 days from ovulation or 72 days from mating)',
  'Kiedy pilnie dzwonić do weterynarza': 'When to call the vet urgently',
  'od owulacji': 'from ovulation',
  'od krycia': 'from mating',
  'Przewidywany poród (ok.)': 'Expected whelping (approx.)',
  'w oknie': 'in window',
  ' (szerokie – liczone od krycia; owulacja z badania zawęża okno)':
      ' (wide – counted from mating; a tested ovulation narrows it)',
  'USG: zwykle od {0} · RTG: od {1} (liczenie szczeniąt najdokładniej po {2})':
      'Ultrasound: usually from {0} · X-ray: from {1} (counting most accurate after {2})',
  'Jeśli lekarz potwierdził owulację (np. progesteron), termin porodu będzie dokładniejszy: 63 dni ± 1 od owulacji. Od samego krycia poród następuje zwykle po 57–72 dniach.': 'If the vet confirmed ovulation (e.g. progesterone), the due date is more accurate: 63 ± 1 days from ovulation. From mating alone whelping usually occurs after 57–72 days.',
  'Terminy są orientacyjne. Bez owulacji potwierdzonej badaniem okno porodu jest szerokie. Przebieg ciąży, żywienie i poród konsultuj z lekarzem weterynarii.': 'Dates are approximate. Without a tested ovulation the whelping window is wide. Discuss pregnancy, feeding and whelping with your vet.',
  'spadek wagi – sprawdź': 'weight loss – check',
  'Szczenię powinno przybierać codziennie i podwoić masę urodzeniową w ok. 7–10 dni. W pierwszych 1–2 dobach niewielki spadek (do ok. 10%) bywa normalny – obserwuj, czy ssie. Większy lub dłuższy spadek, brak przyrostu albo słabe ssanie – skontaktuj się z lekarzem weterynarii.': 'A puppy should gain daily and double its birth weight in about 7–10 days. In the first 1–2 days a small loss (up to about 10%) can be normal – check that it suckles. A larger or longer loss, no gain or weak suckling – contact your vet.',
  'Odrobaczanie zwykle od 2. tygodnia, potem co 2 tygodnie – preparat i schemat ustala lekarz weterynarii. Szczenięta zaczynają chodzić.': 'Deworming usually from week 2, then every 2 weeks – the vet chooses the product and schedule. Puppies start walking.',
  'Pierwsze szczepienie zwykle w 6.–8. tygodniu, kolejne co 2–4 tygodnie do ok. 16. tygodnia (WSAVA) – schemat ustala lekarz. Przegląd miotu w związku.': 'First vaccination usually at 6–8 weeks, then every 2–4 weeks until about 16 weeks (WSAVA) – the vet sets the schedule. Litter inspection at the kennel club.',
  'spadek wagi – skontaktuj się z lekarzem': 'weight loss – contact your vet',
  'niewielki spadek – obserwuj': 'small loss – monitor',
  'brak przyrostu – obserwuj': 'no gain – monitor',
  'wolny przyrost': 'slow gain',

  // --- Trening ---
  'Mniej energii niż zwykle': 'Less energy than usual',
  'Słabszy apetyt': 'Poorer appetite',
  'Mniejsza chęć do pracy': 'Less eager to work',
  'Sztywność, kulawizna lub dyskomfort': 'Stiffness, lameness or discomfort',
  'Gorsze ogólne samopoczucie': 'Generally unwell',
  'Samopoczucie psa (zaznacz, jeśli gorzej niż zwykle)': 'Dog\'s wellbeing (tick if worse than usual)',
  'Monitor obciążenia treningowego': 'Training load monitor',
  'Zaznaczono: {0}. Bez względu na wskaźnik zaplanuj lżejszy dzień, a sztywność, kulawiznę lub utrzymujące się objawy skonsultuj z lekarzem weterynarii.': 'Noted: {0}. Regardless of the indicator plan an easier day, and see your vet about stiffness, lameness or persistent signs.',
  'Dodaj kilka treningów, a porównam obciążenie z ostatnich 7 dni ze zwykłym.':
      'Add a few trainings and I\'ll compare the last 7 days\' load with your usual load.',
  'Za krótka historia': 'History too short',
  'Porównanie obciążenia ma sens po ok. 3–4 tygodniach zapisów. Do tego czasu zwiększaj obciążenie stopniowo i obserwuj psa.': 'Load comparison makes sense after about 3–4 weeks of logs. Until then increase the load gradually and watch the dog.',
  'Obciążenie niższe niż zwykle': 'Load lower than usual',
  'Ostatnie 7 dni były lżejsze niż zwykle. To nie oznacza pełnej regeneracji – przed mocniejszym treningiem oceń samopoczucie psa.': 'The last 7 days were lighter than usual. That doesn\'t mean full recovery – check how the dog feels before a harder session.',
  'Obciążenie podobne do zwykłego': 'Load similar to usual',
  'Obciążenie zbliżone do ostatnich tygodni. Kieruj się też samopoczuciem psa.':
      'Load close to recent weeks. Also go by how the dog feels.',
  'Obciążenie rośnie szybko': 'Load rising quickly',
  'Ten tydzień jest wyraźnie cięższy niż zwykle. Rozważ lżejszy dzień lub regenerację.':
      'This week is clearly harder than usual. Consider an easier or recovery day.',
  'Obciążenie dużo wyższe niż zwykle': 'Load much higher than usual',
  'Ten tydzień jest dużo cięższy niż zwykle. Nagły wzrost obciążenia może zwiększać ryzyko urazu – zaplanuj dzień regeneracji.':
      'This week is much harder than usual. A sudden load increase may raise injury risk – plan a recovery day.',
  'Obciążenie 7 dni / średnia tygodniowa z 4 tygodni: {0}. Umowny zakres „jak zwykle” 0,8–1,3 – to orientacyjny wskaźnik zmiany obciążenia (ACWR), niezwalidowany u psów i nie mierzy zmęczenia.': '7-day load / 4-week weekly average: {0}. The “usual” range 0.8–1.3 is a convention – an approximate load-change indicator (ACWR), not validated in dogs and not a measure of fatigue.',

  // --- Wystawy ---
  'Regulamin Wystaw Psów Rasowych ZKwP (rozdz. IV.5, wersja od 1.01.2024 z późn. zm.) i regulamin tytułów FCI (2024). Sprawdzono 19.11.2026 – przed złożeniem wniosku potwierdź aktualne zasady w ZKwP.': 'ZKwP Dog Show Regulations (ch. IV.5, version from 1 Jan 2024 as amended) and FCI title regulations (2024). Checked 19 Nov 2026 – confirm current rules with ZKwP before applying.',
  'Nie można zweryfikować': 'Cannot verify',
  ' – nie można zweryfikować: uzupełnij nazwiska sędziów': ' – cannot verify: add judges\' names',
  ' – nie można zweryfikować: uzupełnij kraje wystaw': ' – cannot verify: add show countries',
  ' – pominięto {0} wpisy z klasy, w której CWC nie jest przyznawane':
      ' – skipped {0} entries from a class where CWC is not awarded',
  'od 3 różnych sędziów (potwierdzonych: {0})': 'from 3 different judges (confirmed: {0})',
  'od {0} różnych sędziów (potwierdzonych: {1})': 'from {0} different judges (confirmed: {1})',
  'w {0} różnych krajach (potwierdzonych: {1})': 'in {0} different countries (confirmed: {1})',
  'jeden zestaw certyfikatów spełnia wszystkie warunki – nie można zweryfikować bez nazwisk sędziów i krajów':
      'one set of certificates meets all conditions – cannot verify without judges\' names and countries',
  'te same certyfikaty muszą spełniać wszystkie warunki naraz (sędziowie, rodzaj wystawy, odstęp)':
      'the same certificates must meet all conditions at once (judges, show type, time gap)',
  'ustal, czy rasa podlega próbom pracy wg nomenklatury FCI (profil psa) – liczę jak dla rasy bez próby': 'set whether the breed is subject to a working trial per the FCI nomenclature (dog profile) – counting as a breed without a trial',
  'zdana próba pracy z CACT właściwa dla rasy (np. IGP 1 – min. 70% w każdej części)':
      'passed breed-appropriate working trial with CACT (e.g. IGP 1 – min. 70% in each part)',
  'Trzykrotnie tytuł Zwycięzcy Młodzieży od 3 różnych sędziów, co najmniej raz na wystawie specjalistycznej, klubowej lub międzynarodowej. Bez wymaganego odstępu czasu.': 'Junior Winner title three times from 3 different judges, at least once at a specialty, club or international show. No time gap required.',
  'Trzy CWC od trzech różnych sędziów, co najmniej jedno na wystawie międzynarodowej, klubowej lub specjalistycznej. Między pierwszym a ostatnim CWC co najmniej 6 miesięcy. CWC przyznaje się za ocenę doskonałą z 1. lokatą w klasie pośredniej, otwartej, użytkowej lub championów (pies powyżej 15 miesięcy).': 'Three CWC from three different judges, at least one at an international, club or specialty show. At least 6 months between the first and the last CWC. CWC is awarded for an excellent grade with 1st place in intermediate, open, working or champion class (dog over 15 months).',
  'Pies z zatwierdzonym tytułem Champion Polski po jego otrzymaniu zdobywa 3 CWC w klasie championów od 3 sędziów na wystawach międzynarodowych, championów lub Światowej Wystawie Ras Polskich w Polsce. Odstęp czasu nie jest wymagany. Aplikacja liczy wystawy oznaczone jako międzynarodowe – CWC z wystawy championów lub ŚWRP sprawdź samodzielnie.': 'After the Polish Champion title is confirmed, the dog wins 3 CWC in champion class from 3 judges at international shows, champion shows or the World Show of Polish Breeds in Poland. No time gap required. The app counts shows marked as international – check CWC from champion shows or the World Show of Polish Breeds yourself.',
  'Trzykrotnie tytuł Zwycięzca Weteran od 3 różnych sędziów, co najmniej raz na wystawie specjalistycznej, klubowej lub międzynarodowej. Klasa weteranów – psy, które ukończyły 8 lat.': 'Veteran Winner title three times from 3 different judges, at least once at a specialty, club or international show. Veteran class – dogs aged 8 years or more.',
  'Rasy podlegające próbom pracy: 2 CACIB od 2 sędziów w 2 krajach, min. rok i 1 dzień między pierwszym a ostatnim, oraz zdana próba pracy z CACT właściwa dla rasy (np. gr. I–III: IGP/IPO kl. 1 z min. 70% w każdej części; gr. 7: polowa próba „bardzo dobry”). Data próby nie ma znaczenia.': 'Breeds subject to a working trial: 2 CACIB from 2 judges in 2 countries, at least 1 year and 1 day between first and last, plus a passed breed-appropriate working trial with CACT (e.g. groups I–III: IGP/IPO class 1 with min. 70% in each part; group 7: field trial “very good”). The trial date doesn\'t matter.',
  'Nie ustawiono – sprawdź w nomenklaturze FCI swojej rasy (wpływa na wymagania C.I.B.)':
      'Not set – check your breed in the FCI nomenclature (affects C.I.B. requirements)',
  'To, czy rasa podlega próbom pracy, wynika z nomenklatury FCI dla danej rasy (nie z numeru grupy). Ustaw to w profilu psa. Zdaną próbę zaznacz w Celach (np. IGP 1 – zaliczone).': 'Whether a breed is subject to a working trial comes from the FCI nomenclature for that breed (not the group number). Set it in the dog profile. Mark a passed trial in Goals (e.g. IGP 1 – passed).',

  // --- Pogoda ---
  'krótka kufa': 'short muzzle',
  'gęsta szata lub budowa utrudniająca chłodzenie': 'dense coat or build that hinders cooling',
  'nadwaga': 'overweight',
  'wiek senioralny': 'senior age',
  'młody pies': 'young dog',
  'predyspozycja do chorób serca': 'predisposition to heart disease',
  '{0}°C': '{0}°C',
  'wilgotność {0}% utrudnia chłodzenie dyszeniem': 'humidity {0}% hinders cooling by panting',
  'silne nasłonecznienie': 'strong sunshine',
  'długi trening ({0} min)': 'long session ({0} min)',
  'Wysokie ryzyko przegrzania przy biegu. Wybierz spokojny spacer w cieniu, trening przy wodzie albo wczesny poranek. Przerwij od razu, gdy pies mocno dyszy, zwalnia lub się zatacza.': 'High risk of overheating when running. Choose a calm walk in the shade, training by water or early morning. Stop at once if the dog pants heavily, slows down or staggers.',
  'Ciepło – krótki, spokojny spacer w cieniu, woda, bez zabaw w biegu.':
      'Warm – a short calm walk in the shade, water, no running games.',
  'Podwyższone ryzyko. Skróć trening, zwolnij, rób przerwy w cieniu i podawaj wodę. Obserwuj język, oddech i tempo psa.': 'Increased risk. Shorten the session, slow down, take breaks in the shade and give water. Watch the dog\'s tongue, breathing and pace.',
  'Warunki zwykle dobre, ale obserwuj psa – przegrzanie zdarza się także w chłodniejsze dni przy dużym wysiłku.':
      'Conditions are usually good, but watch the dog – overheating also happens on cooler days with hard effort.',
  'Wysokie ryzyko przegrzania': 'High risk of overheating',
  'Czynniki: {0}.': 'Factors: {0}.',
  'Temperatura odczuwalna liczona jest dla ludzi – pies chłodzi się dyszeniem, więc wilgotność i słońce znaczą dla niego więcej. To szacunek, nie gwarancja bezpieczeństwa.': '“Feels like” temperature is calculated for humans – dogs cool by panting, so humidity and sun matter more for them. This is an estimate, not a safety guarantee.',
  'Brak danych o pogodzie. W ciepły, wilgotny lub słoneczny dzień biegnij krócej, rób przerwy w cieniu i zabierz wodę.':
      'No weather data. On a warm, humid or sunny day run shorter, take breaks in the shade and bring water.',

  // --- Zdrowie ---
  'Wścieklizna jest w Polsce obowiązkowa – termin kolejnej dawki wpisz z książeczki. Pozostałe szczepienia są zalecane; schemat ustala lekarz (wg WSAVA szczepienia podstawowe dorosłego psa zwykle nie częściej niż co 3 lata, leptospiroza co rok).': 'Rabies vaccination is mandatory in Poland – enter the next dose date from the vaccination book. Other vaccines are recommended; the vet sets the schedule (per WSAVA, adult core vaccines usually no more often than every 3 years, leptospirosis yearly).',
  'Częstotliwość zależy od trybu życia psa (ESCCAP): zwykle 4 razy w roku, częściej przy dużym ryzyku, rzadziej przy badaniu kału. Termin to propozycja – ustal własny schemat z lekarzem.': 'Frequency depends on the dog\'s lifestyle (ESCCAP): usually 4 times a year, more often at high risk, less often with faecal testing. The date is a suggestion – agree your own schedule with the vet.',
  'Odstęp zależy od preparatu – sprawdź ulotkę. Dla znanych preparatów proponuję termin z ulotki.':
      'The interval depends on the product – check the leaflet. For known products I suggest the leaflet interval.',
  'Wpisz wynik tak, jak na wyniku lub certyfikacie. Aplikacja nie interpretuje wyników badań i nie stawia diagnoz.':
      'Enter the result exactly as on the report or certificate. The app does not interpret results or make diagnoses.',
  'Pies na pełnoporcjowej karmie zwykle nie potrzebuje suplementów – także pies sportowy. Stosuj je po konsultacji z lekarzem i licz kalorie w Żywieniu.': 'A dog on a complete food usually doesn\'t need supplements – sport dogs included. Use them after talking to your vet and count their calories in Nutrition.',
  'Proponowany termin – zmień go, jeśli lekarz ustalił inny.':
      'Suggested date – change it if your vet set a different one.',

  // --- Poradniki ---
  'Agility to tor przeszkód pokonywany na czas. Zaczynamy od podstaw prowadzenia i niskich przeszkód. Pełna wysokość skoków, przeszkody kontaktowe w pełnej wysokości i dużo powtórzeń slalomu dopiero po zakończeniu wzrostu (zwykle 12–18 mies., u ras dużych i olbrzymich później – w razie wątpliwości zapytaj lekarza). Przed każdym treningiem rozgrzewka; pies powinien mieć dobrą kondycję i prawidłową masę ciała.': 'Agility is a timed obstacle course. Start with handling basics and low obstacles. Full jump height, full-height contact obstacles and many weave repetitions only after growth has finished (usually 12–18 months, later in large and giant breeds – ask your vet if unsure). Warm up before every session; the dog should be fit and at a healthy weight.',
  'Pierwsza tyczka zawsze przy lewym barku psa – pies wchodzi między 1. a 2. tyczkę od jej prawej strony.': 'The first pole is always at the dog\'s left shoulder – the dog enters between poles 1 and 2 from the right side of pole 1.',
  'To najtrudniejsza przeszkoda – potrzebuje miesięcy. U młodego psa tylko krótkie sesje, bo slalom mocno obciąża kręgosłup i barki.': 'This is the hardest obstacle – it takes months. Young dogs only short sessions, as weaving strains the spine and shoulders.',
  'Zwiększaj tygodniowy dystans stopniowo – orientacyjnie o ok. 10% (to umowna zasada ze sportu ludzi, nie granica bezpieczeństwa).':
      'Increase weekly distance gradually – roughly 10% (a convention from human sport, not a safety limit).',
  'Długie trasy tylko z dorosłym psem po zakończeniu wzrostu i po kontroli u weterynarza. Szczenię i senior – krótkie odcinki.': 'Long routes only with an adult dog that has finished growing and had a vet check. Puppies and seniors – short sections.',
  'Szczenię najłatwiej oswaja świat w okresie wrażliwym (ok. 3.–14. tydzień życia), później idzie to wolniej, ale dorosły pies też się uczy. Pokazuj nowe rzeczy z dystansu, krótko i z nagrodą. Pies może zawsze się wycofać.': 'A puppy gets used to the world most easily in the sensitive period (about weeks 3–14); later it is slower, but adult dogs learn too. Show new things from a distance, briefly and with a reward. The dog can always retreat.',
  'Jedno złe doświadczenie potrafi zostać na długo. Szczenię przed pełnym szczepieniem poznaje tylko zdrowe, zaszczepione psy w czystym miejscu – zapytaj lekarza o bezpieczny plan.': 'One bad experience can last a long time. Before full vaccination a puppy meets only healthy, vaccinated dogs in a clean place – ask your vet for a safe plan.',
  'Obrona (dział C w IGP) to sport, nie szkolenie psa do atakowania ludzi. Ćwicz wyłącznie w klubie, pod okiem doświadczonego pozoranta i instruktora. Pies musi być zdrowy i dojrzały fizycznie – u młodego psa tylko zabawa i budowanie chwytu bez szarpania i obciążeń.': 'Protection (IGP phase C) is a sport, not training a dog to attack people. Practise only at a club with an experienced helper and instructor. The dog must be healthy and physically mature – a young dog only plays and builds the grip without yanking or loads.',
  'Pozorant stopniowo dodaje lekki nacisk i ruch – u młodego psa bez podnoszenia i gwałtownego szarpania.':
      'The helper gradually adds light pressure and movement – with a young dog no lifting or sharp yanking.',
  'Wyłącznie u dorosłego, przygotowanego kondycyjnie psa, po opanowaniu chwytu i „puść”.':
      'Only with an adult, physically conditioned dog that has mastered the grip and “out”.',
  'Do początku okna':
      'To start of window',
  'Jeden wynik nie potwierdza owulacji. Potrzebna jest seria badań (zwykle co 1–3 dni), którą ocenia lekarz weterynarii.':
      'A single result does not confirm ovulation. A series of tests (usually every 1–3 days), interpreted by a vet, is needed.',
  'Możliwy poród':
      'Possible whelping',
  'Możliwy poród: {0}':
      'Possible whelping: {0}',
  'Od samego krycia termin jest szeroki (57–72 dni). Dokładniejszy (62–64 dni) daje owulacja potwierdzona badaniem progesteronu.':
      'From the mating date alone the range is wide (57–72 days). Ovulation confirmed by progesterone testing gives a narrower one (62–64 days).',
  'Porady treningowe, nie regulamin zawodów ani egzaminu.':
      'Training tips, not competition or trial rules.',
  'Seria w toku. Wynik ocenia lekarz weterynarii na podstawie całej serii.':
      'Series in progress. The vet interprets the result from the whole series.',
  'W serii nie widać wzrostu. Kolejne badania i ich ocenę zaplanuj z lekarzem weterynarii.':
      'No rise is visible in the series. Plan further tests and their interpretation with your vet.',
  'W serii widać wzrost progesteronu. Czy i kiedy nastąpiła owulacja, ustala lekarz weterynarii – aplikacja nie wpisuje jej sama.':
      'The series shows a progesterone rise. Whether and when ovulation occurred is for the vet to determine – the app does not enter it by itself.',
  'Warunki spełnione':
      'Requirements met',
  'Wymagania egzaminu (wiek psa, przebieg, punktacja, dopuszczenie) sprawdź w aktualnym regulaminie organizatora (ZKwP, FCI). Regulamin IGP FCI zmienił się od 1.01.2025. Aplikacja nie zastępuje regulaminu.':
      'Check trial requirements (dog’s age, procedure, scoring, eligibility) in the organiser’s current rules (national kennel club, FCI). The FCI IGP rules changed on 1 Jan 2025. The app does not replace the rules.',
  'Wymagania są spełnione według Twoich wpisów. To nie jest przyznanie tytułu – tytuł nadaje ZKwP (lub FCI dla C.I.B.) po złożeniu wniosku z kopiami kart ocen.':
      'Requirements are met according to your entries. This is not the award of the title – the kennel club (or FCI for C.I.B.) confirms it after you apply with copies of the critiques.',
  'Znana jest tylko data krycia, więc nie da się wskazać jednego dnia porodu. Poród zwykle wypada 57–72 dni od krycia. Owulacja potwierdzona badaniem (progesteron) zawęża termin do ok. 62–64 dni.':
      'Only the mating date is known, so no single whelping day can be given. Whelping usually falls 57–72 days after mating. Ovulation confirmed by testing (progesterone) narrows it to about 62–64 days.',
  'jutro':
      'tomorrow',
  'ok. {0} ({1} – {2})':
      'approx. {0} ({1} – {2})',
  'tytuł Champion Polski – wymagania wg wpisów spełnione, ale brak potwierdzenia przyznania tytułu (zaznacz w Celach, gdy ZKwP go zatwierdzi)':
      'Polish Champion title – requirements met per your entries, but the award is not confirmed (mark it in Goals once the kennel club approves it)',
  'zatwierdzony tytuł Champion Polski':
      'confirmed Polish Champion title',
  'Środek okna porodu':
      'Middle of the whelping window',
  '63. dzień to tylko orientacyjny środek okna. Gdy znane jest tylko krycie, poród może być wyraźnie wcześniej lub później – patrz okno porodu powyżej. Po jego przekroczeniu skontaktuj się z lekarzem.':
      'Day 63 is only an approximate middle of the window. When only the mating is known, whelping may be noticeably earlier or later – see the whelping window above. Contact your vet once it has passed.',
};
