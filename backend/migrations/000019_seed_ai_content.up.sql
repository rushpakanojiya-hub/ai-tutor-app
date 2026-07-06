-- 1) Add the missing Biology lesson (Biology subject already existed from Day 2 seed, with no lessons yet).
INSERT INTO lessons (subject_id, title, description, video_url, pdf_url, duration, order_number)
SELECT s.id, 'Introduction to Biology', 'The cell as the basic unit of life, and how cells build tissues, organs, and organisms.', NULL, NULL, 8, 1
FROM subjects s WHERE s.name = 'Biology'
ON CONFLICT DO NOTHING;

-- 2) AI-generated content per flagship lesson (explanation, summary, key points, examples, practice questions, quiz).
INSERT INTO lesson_ai_content (lesson_id, explanation, summary, key_points, examples, practice_questions, quiz_json)
SELECT l.id, $ai$Mathematics is the study of numbers, quantities, shapes, and the patterns and relationships between them. It gives us a precise, universal language for describing the world: from counting objects, to measuring distances, to modeling how populations grow or how planets orbit the sun. At its core, mathematics is built from a small set of basic ideas (numbers, operations, and logical rules) that combine to describe almost anything quantifiable.$ai$, $ai$Math is the language of quantities, shapes, and patterns. Its major branches include arithmetic, algebra, geometry, and statistics, and mathematical thinking builds reasoning skills useful far beyond the classroom.$ai$,
    $js$["Mathematics studies numbers, shapes, and the relationships between them.", "Arithmetic covers basic operations: addition, subtraction, multiplication, division.", "Algebra uses symbols (like x) to represent unknown values.", "Geometry studies shapes, angles, and space.", "Statistics is about collecting and interpreting data."]$js$::jsonb, $js$["Counting 5 apples uses arithmetic.", "Solving 'x + 3 = 10' for x uses algebra.", "Finding the area of a room uses geometry.", "Calculating a class's average test score uses statistics."]$js$::jsonb, $js$["What are the four branches of mathematics mentioned in this lesson?", "Why is mathematics sometimes called a 'universal language'?", "Give one real-life example where you used arithmetic today."]$js$::jsonb, $js$[{"question": "Which branch of mathematics uses letters like x and y to represent unknown numbers?", "options": ["Arithmetic", "Algebra", "Geometry", "Statistics"], "correct_option": 1}, {"question": "Which branch of mathematics studies shapes and angles?", "options": ["Algebra", "Statistics", "Geometry", "Arithmetic"], "correct_option": 2}, {"question": "Collecting and interpreting data falls under which branch?", "options": ["Statistics", "Geometry", "Algebra", "Arithmetic"], "correct_option": 0}]$js$::jsonb
FROM lessons l JOIN subjects s ON s.id = l.subject_id
WHERE s.name = 'Mathematics' AND l.title = 'Introduction'
ON CONFLICT (lesson_id) DO UPDATE SET
    explanation = EXCLUDED.explanation,
    summary = EXCLUDED.summary,
    key_points = EXCLUDED.key_points,
    examples = EXCLUDED.examples,
    practice_questions = EXCLUDED.practice_questions,
    quiz_json = EXCLUDED.quiz_json,
    updated_at = NOW();

INSERT INTO lesson_ai_content (lesson_id, explanation, summary, key_points, examples, practice_questions, quiz_json)
SELECT l.id, $ai$Algebra is the branch of mathematics that uses symbols, usually letters like x and y, to represent numbers we don't yet know. An equation is a statement that two expressions are equal, and 'solving' an equation means finding the value of the unknown variable that makes the statement true. The key technique is keeping both sides of the equation balanced: whatever operation you perform on one side, you must perform on the other.$ai$, $ai$Algebra represents unknown numbers with variables and solves equations by performing the same operation on both sides to isolate the variable.$ai$,
    $js$["A variable is a symbol representing an unknown value.", "An equation states that two expressions are equal.", "Solving an equation means isolating the variable using balanced operations.", "PEMDAS defines the order of operations: Parentheses, Exponents, Multiplication/Division, Addition/Subtraction."]$js$::jsonb, $js$["x + 5 = 12 -> subtract 5 from both sides -> x = 7", "3x = 21 -> divide both sides by 3 -> x = 7", "x / 2 = 4 -> multiply both sides by 2 -> x = 8"]$js$::jsonb, $js$["Solve for x: x + 8 = 15", "Solve for x: 4x = 32", "Solve for x: 2x + 3 = 11"]$js$::jsonb, $js$[{"question": "What is the value of x in 'x + 5 = 12'?", "options": ["5", "7", "12", "17"], "correct_option": 1}, {"question": "What operation isolates x in '3x = 21'?", "options": ["Add 3", "Subtract 21", "Divide by 3", "Multiply by 3"], "correct_option": 2}, {"question": "In PEMDAS, what comes right after Parentheses?", "options": ["Addition", "Multiplication", "Exponents", "Subtraction"], "correct_option": 2}]$js$::jsonb
FROM lessons l JOIN subjects s ON s.id = l.subject_id
WHERE s.name = 'Mathematics' AND l.title = 'Algebra'
ON CONFLICT (lesson_id) DO UPDATE SET
    explanation = EXCLUDED.explanation,
    summary = EXCLUDED.summary,
    key_points = EXCLUDED.key_points,
    examples = EXCLUDED.examples,
    practice_questions = EXCLUDED.practice_questions,
    quiz_json = EXCLUDED.quiz_json,
    updated_at = NOW();

INSERT INTO lesson_ai_content (lesson_id, explanation, summary, key_points, examples, practice_questions, quiz_json)
SELECT l.id, $ai$Geometry is the branch of mathematics concerned with shapes, sizes, angles, and the space they occupy. Every shape is built from basic elements: points, lines, and angles. Understanding a few core shapes (triangles, squares, circles) and how to measure perimeter (the distance around a shape) and area (the space inside it) unlocks the ability to reason about the physical world, from room layouts to land surveying.$ai$, $ai$Geometry studies shapes, angles, perimeter, and area, using triangles, squares, and circles as building blocks for more complex spatial reasoning.$ai$,
    $js$["A triangle has 3 sides and its angles sum to 180 degrees.", "A square has 4 equal sides and 4 right angles (90 degrees each).", "A circle's points are all equidistant from its center.", "Perimeter is the distance around a shape; area is the space inside it."]$js$::jsonb, $js$["Rectangle perimeter = 2 x (length + width)", "Rectangle area = length x width", "Circle area = pi x radius squared"]$js$::jsonb, $js$["Find the perimeter of a rectangle with length 8 and width 5.", "Find the area of a square with side length 6.", "Is a 45-degree angle acute, right, or obtuse?"]$js$::jsonb, $js$[{"question": "How many degrees do a triangle's angles sum to?", "options": ["90", "180", "270", "360"], "correct_option": 1}, {"question": "What is the formula for a rectangle's area?", "options": ["length + width", "2 x (length + width)", "length x width", "length / width"], "correct_option": 2}, {"question": "An angle greater than 90 but less than 180 degrees is called:", "options": ["Acute", "Right", "Obtuse", "Straight"], "correct_option": 2}]$js$::jsonb
FROM lessons l JOIN subjects s ON s.id = l.subject_id
WHERE s.name = 'Mathematics' AND l.title = 'Geometry'
ON CONFLICT (lesson_id) DO UPDATE SET
    explanation = EXCLUDED.explanation,
    summary = EXCLUDED.summary,
    key_points = EXCLUDED.key_points,
    examples = EXCLUDED.examples,
    practice_questions = EXCLUDED.practice_questions,
    quiz_json = EXCLUDED.quiz_json,
    updated_at = NOW();

INSERT INTO lesson_ai_content (lesson_id, explanation, summary, key_points, examples, practice_questions, quiz_json)
SELECT l.id, $ai$Physics is the natural science that studies matter, energy, motion, and the forces that govern how objects behave. It explains everything from why an apple falls to the ground (gravity) to how a smartphone screen lights up (electromagnetism). Physics relies on the scientific method: physicists observe the world, form a hypothesis, test it with experiments, and refine their understanding based on the evidence they gather.$ai$, $ai$Physics studies matter, energy, and motion through branches like mechanics, thermodynamics, and electromagnetism, using the scientific method to build reliable, predictive models of nature.$ai$,
    $js$["Mechanics studies motion and forces.", "Thermodynamics studies heat and energy transfer.", "Electromagnetism studies electricity, magnetism, and light.", "The scientific method: observe, hypothesize, test, refine."]$js$::jsonb, $js$["A ball rolling and slowing due to friction is a mechanics example.", "A cup of hot tea cooling down is a thermodynamics example.", "A phone charging wirelessly is an electromagnetism example."]$js$::jsonb, $js$["Name the four steps of the scientific method.", "Which branch of physics would explain why a spoon in hot soup gets warm?", "Give one everyday example of mechanics in action."]$js$::jsonb, $js$[{"question": "Which branch of physics studies motion and forces?", "options": ["Thermodynamics", "Mechanics", "Electromagnetism", "Optics"], "correct_option": 1}, {"question": "What is the first step of the scientific method?", "options": ["Test", "Refine", "Observe", "Hypothesize"], "correct_option": 2}, {"question": "Heat transfer is studied under which branch of physics?", "options": ["Mechanics", "Thermodynamics", "Electromagnetism", "Modern Physics"], "correct_option": 1}]$js$::jsonb
FROM lessons l JOIN subjects s ON s.id = l.subject_id
WHERE s.name = 'Physics' AND l.title = 'Introduction to Physics'
ON CONFLICT (lesson_id) DO UPDATE SET
    explanation = EXCLUDED.explanation,
    summary = EXCLUDED.summary,
    key_points = EXCLUDED.key_points,
    examples = EXCLUDED.examples,
    practice_questions = EXCLUDED.practice_questions,
    quiz_json = EXCLUDED.quiz_json,
    updated_at = NOW();

INSERT INTO lesson_ai_content (lesson_id, explanation, summary, key_points, examples, practice_questions, quiz_json)
SELECT l.id, $ai$Chemistry is the study of matter: what it's made of, how it behaves, and how it changes when it interacts with other matter. All matter exists in one of three common states (solid, liquid, gas), and changes can be physical (like ice melting, where the substance stays the same) or chemical (like wood burning, which creates entirely new substances). Chemistry bridges physics and biology, explaining everything from cooking to medicine to materials science.$ai$, $ai$Chemistry studies matter's composition and behavior, distinguishing physical changes (appearance only) from chemical changes (new substances formed).$ai$,
    $js$["Solids have a fixed shape and volume.", "Liquids have a fixed volume but take their container's shape.", "Gases have no fixed shape or volume.", "A physical change alters appearance; a chemical change creates new substances."]$js$::jsonb, $js$["Ice melting into water is a physical change.", "Wood burning into ash and smoke is a chemical change.", "Water boiling into steam is a physical change (still H2O)."]$js$::jsonb, $js$["Name the three common states of matter.", "Is rusting iron a physical or chemical change? Why?", "Give one example each of a physical and a chemical change."]$js$::jsonb, $js$[{"question": "Which state of matter has no fixed shape or volume?", "options": ["Solid", "Liquid", "Gas", "Plasma"], "correct_option": 2}, {"question": "Ice melting into water is an example of a:", "options": ["Chemical change", "Physical change", "Nuclear change", "Biological change"], "correct_option": 1}, {"question": "Which of these is a chemical change?", "options": ["Water boiling", "Wood burning", "Ice melting", "Sugar dissolving"], "correct_option": 1}]$js$::jsonb
FROM lessons l JOIN subjects s ON s.id = l.subject_id
WHERE s.name = 'Chemistry' AND l.title = 'Introduction to Chemistry'
ON CONFLICT (lesson_id) DO UPDATE SET
    explanation = EXCLUDED.explanation,
    summary = EXCLUDED.summary,
    key_points = EXCLUDED.key_points,
    examples = EXCLUDED.examples,
    practice_questions = EXCLUDED.practice_questions,
    quiz_json = EXCLUDED.quiz_json,
    updated_at = NOW();

INSERT INTO lesson_ai_content (lesson_id, explanation, summary, key_points, examples, practice_questions, quiz_json)
SELECT l.id, $ai$Biology is the science of life and living organisms. It studies everything from the tiniest single-celled bacteria to the largest whales, examining how living things grow, reproduce, and interact with their environment. The cell is the basic unit of life: every living organism is made of one or more cells. Groups of similar cells form tissues, tissues form organs, and organs work together as organisms.$ai$, $ai$Biology studies living organisms, starting from the cell (life's basic unit) up through tissues, organs, and whole organisms.$ai$,
    $js$["The cell is the basic unit of life.", "Tissues are groups of similar cells working together.", "Organs are made of different tissues working together for a function.", "An organism is a complete living thing made of organs working together."]$js$::jsonb, $js$["A single red blood cell is a cell.", "Muscle tissue is made of many muscle cells together.", "The heart is an organ made of muscle and other tissues.", "A human being is an organism made of many organs."]$js$::jsonb, $js$["What is the basic unit of life called?", "Put in order from smallest to largest: organ, cell, tissue, organism.", "Name one organ in the human body and its main tissue type."]$js$::jsonb, $js$[{"question": "What is the basic unit of life?", "options": ["Tissue", "Organ", "Cell", "Organism"], "correct_option": 2}, {"question": "A group of similar cells working together is called a:", "options": ["Organ", "Tissue", "Organism", "Molecule"], "correct_option": 1}, {"question": "Which is the correct order from smallest to largest?", "options": ["Organism -> Organ -> Tissue -> Cell", "Cell -> Tissue -> Organ -> Organism", "Tissue -> Cell -> Organism -> Organ", "Organ -> Cell -> Tissue -> Organism"], "correct_option": 1}]$js$::jsonb
FROM lessons l JOIN subjects s ON s.id = l.subject_id
WHERE s.name = 'Biology' AND l.title = 'Introduction to Biology'
ON CONFLICT (lesson_id) DO UPDATE SET
    explanation = EXCLUDED.explanation,
    summary = EXCLUDED.summary,
    key_points = EXCLUDED.key_points,
    examples = EXCLUDED.examples,
    practice_questions = EXCLUDED.practice_questions,
    quiz_json = EXCLUDED.quiz_json,
    updated_at = NOW();

INSERT INTO lesson_ai_content (lesson_id, explanation, summary, key_points, examples, practice_questions, quiz_json)
SELECT l.id, $ai$The earliest complex human societies arose near major rivers, where fertile soil supported farming and growing populations: Mesopotamia along the Tigris and Euphrates, Egypt along the Nile, the Indus Valley in South Asia, and China along the Yellow River. Each civilization developed unique innovations, from writing systems to monumental architecture, that still influence how societies function today. Later, the Roman Empire built on these foundations, spreading law, engineering, and governance across a vast territory.$ai$, $ai$Early river-valley civilizations (Mesopotamia, Egypt, Indus Valley, China) developed writing, law, and architecture; the Roman Empire later spread law and engineering across a huge territory.$ai$,
    $js$["Mesopotamia invented writing (cuneiform) and early law codes.", "Egypt built monumental pyramids and developed a solar calendar.", "The Indus Valley built planned cities with advanced drainage systems.", "Ancient China developed silk production and early bureaucracy.", "The Roman Empire spread law, engineering, and governance across Europe and beyond."]$js$::jsonb, $js$["The Code of Hammurabi is an early Mesopotamian law code.", "The Great Pyramid of Giza is a famous Egyptian monument.", "Roman aqueducts show advanced engineering used to transport water."]$js$::jsonb, $js$["Name the four early river-valley civilizations discussed in this lesson.", "What was one major achievement of Mesopotamia?", "How did the Roman Empire influence later societies?"]$js$::jsonb, $js$[{"question": "Which civilization invented one of the earliest writing systems (cuneiform)?", "options": ["Egypt", "Mesopotamia", "Indus Valley", "China"], "correct_option": 1}, {"question": "The Great Pyramid of Giza belongs to which ancient civilization?", "options": ["Mesopotamia", "China", "Egypt", "Rome"], "correct_option": 2}, {"question": "Which empire is known for spreading law and engineering (like aqueducts) across a vast territory?", "options": ["Indus Valley", "Roman Empire", "Ancient China", "Mesopotamia"], "correct_option": 1}]$js$::jsonb
FROM lessons l JOIN subjects s ON s.id = l.subject_id
WHERE s.name = 'History' AND l.title = 'Ancient Civilizations'
ON CONFLICT (lesson_id) DO UPDATE SET
    explanation = EXCLUDED.explanation,
    summary = EXCLUDED.summary,
    key_points = EXCLUDED.key_points,
    examples = EXCLUDED.examples,
    practice_questions = EXCLUDED.practice_questions,
    quiz_json = EXCLUDED.quiz_json,
    updated_at = NOW();

INSERT INTO lesson_ai_content (lesson_id, explanation, summary, key_points, examples, practice_questions, quiz_json)
SELECT l.id, $ai$India was under British colonial rule for nearly 200 years. Growing economic hardship and a rising demand for self-governance fueled a broad independence movement through the early 20th century. Mahatma Gandhi led nonviolent resistance (Satyagraha), including the Salt March and the Quit India Movement. Jawaharlal Nehru, a key leader of the Indian National Congress, later became independent India's first Prime Minister, while Bhagat Singh represented the movement's more revolutionary strand. India gained independence on August 15, 1947, though the transition also led to the partition of British India into India and Pakistan.$ai$, $ai$The Indian independence movement, led by figures like Gandhi (nonviolent resistance), Nehru, and Bhagat Singh, ended nearly 200 years of British rule on August 15, 1947, alongside the partition into India and Pakistan.$ai$,
    $js$["Mahatma Gandhi led nonviolent resistance (Satyagraha), including the Salt March.", "Jawaharlal Nehru led the Indian National Congress and became India's first Prime Minister.", "Bhagat Singh represented the more revolutionary strand of the movement.", "India became independent on August 15, 1947.", "Independence was accompanied by the partition of India and Pakistan."]$js$::jsonb, $js$["The Salt March (1930) was a nonviolent protest against the British salt tax.", "The Quit India Movement (1942) demanded an end to British rule."]$js$::jsonb, $js$["What method of resistance did Mahatma Gandhi use?", "On what date did India gain independence?", "Name one leader associated with the revolutionary strand of the movement."]$js$::jsonb, $js$[{"question": "What nonviolent method of resistance is associated with Mahatma Gandhi?", "options": ["Guerrilla warfare", "Satyagraha", "Diplomacy", "Armed rebellion"], "correct_option": 1}, {"question": "Who became India's first Prime Minister after independence?", "options": ["Mahatma Gandhi", "Bhagat Singh", "Jawaharlal Nehru", "Lord Mountbatten"], "correct_option": 2}, {"question": "On what date did India gain independence?", "options": ["January 26, 1950", "August 15, 1947", "October 2, 1869", "March 12, 1930"], "correct_option": 1}]$js$::jsonb
FROM lessons l JOIN subjects s ON s.id = l.subject_id
WHERE s.name = 'History' AND l.title = 'Indian Independence Movement'
ON CONFLICT (lesson_id) DO UPDATE SET
    explanation = EXCLUDED.explanation,
    summary = EXCLUDED.summary,
    key_points = EXCLUDED.key_points,
    examples = EXCLUDED.examples,
    practice_questions = EXCLUDED.practice_questions,
    quiz_json = EXCLUDED.quiz_json,
    updated_at = NOW();

INSERT INTO lesson_ai_content (lesson_id, explanation, summary, key_points, examples, practice_questions, quiz_json)
SELECT l.id, $ai$Flutter is an open-source UI framework created by Google for building natively compiled applications for mobile, web, and desktop from a single codebase, using the Dart programming language. In Flutter, everything you see on screen is a widget: buttons, text, layout containers, even the app itself. Widgets combine to build a UI, and Flutter's 'hot reload' feature lets developers see code changes instantly without restarting the app, making UI development fast and iterative.$ai$, $ai$Flutter lets developers build native apps for multiple platforms from one Dart codebase, composing everything from widgets, with hot reload for fast iteration.$ai$,
    $js$["Flutter apps are written in the Dart programming language.", "Everything visible in a Flutter app is a widget.", "Hot reload shows code changes instantly without restarting the app.", "One codebase can target Android, iOS, web, and desktop."]$js$::jsonb, $js$["Text('Hello, Flutter!') displays a text widget.", "A Column widget arranges its children vertically.", "An ElevatedButton widget displays a clickable button."]$js$::jsonb, $js$["What programming language does Flutter use?", "What is a widget in Flutter?", "What does 'hot reload' let a developer do?"]$js$::jsonb, $js$[{"question": "What programming language is used to write Flutter apps?", "options": ["Java", "Swift", "Dart", "Kotlin"], "correct_option": 2}, {"question": "In Flutter, buttons, text, and layouts are all examples of:", "options": ["Packages", "Widgets", "Plugins", "Themes"], "correct_option": 1}, {"question": "What feature lets you see code changes instantly without restarting the app?", "options": ["Hot reload", "Cold start", "Live share", "Fast build"], "correct_option": 0}]$js$::jsonb
FROM lessons l JOIN subjects s ON s.id = l.subject_id
WHERE s.name = 'Flutter' AND l.title = 'Introduction to Flutter'
ON CONFLICT (lesson_id) DO UPDATE SET
    explanation = EXCLUDED.explanation,
    summary = EXCLUDED.summary,
    key_points = EXCLUDED.key_points,
    examples = EXCLUDED.examples,
    practice_questions = EXCLUDED.practice_questions,
    quiz_json = EXCLUDED.quiz_json,
    updated_at = NOW();

INSERT INTO lesson_ai_content (lesson_id, explanation, summary, key_points, examples, practice_questions, quiz_json)
SELECT l.id, $ai$Go (or Golang) is an open-source programming language created at Google, designed for simplicity, fast compilation, and strong built-in support for concurrent programs. It's widely used for backend servers, APIs, and cloud infrastructure. Every Go program starts with a 'package main' declaration and a 'main' function, the entry point where execution begins. Go compiles directly to a single, fast, native binary, which makes deployment simple.$ai$, $ai$Go is a simple, fast-compiling language built for concurrent backend systems, where every program starts from a 'main' function and compiles to a single native binary.$ai$,
    $js$["Go programs start with 'package main' and a 'main' function.", "Go compiles to a single, fast, native binary.", "Go has built-in support for concurrency via goroutines.", "Go's simple, readable syntax is strongly typed."]$js$::jsonb, $js$["package main; import \"fmt\"; func main() { fmt.Println(\"Hello, Go!\") }", "The Gin framework is commonly used to build REST APIs in Go."]$js$::jsonb, $js$["What is the name of the function where every Go program begins execution?", "Name one reason developers choose Go for backend systems.", "What does Go compile a program into?"]$js$::jsonb, $js$[{"question": "Which function is the entry point of every Go program?", "options": ["start()", "main()", "init()", "run()"], "correct_option": 1}, {"question": "What does Go compile a program into?", "options": ["A virtual machine bytecode", "A single native binary", "An interpreted script", "A Java archive"], "correct_option": 1}, {"question": "What Go feature provides built-in support for concurrent programs?", "options": ["Threads", "Goroutines", "Callbacks", "Promises"], "correct_option": 1}]$js$::jsonb
FROM lessons l JOIN subjects s ON s.id = l.subject_id
WHERE s.name = 'Golang' AND l.title = 'Go Language Fundamentals'
ON CONFLICT (lesson_id) DO UPDATE SET
    explanation = EXCLUDED.explanation,
    summary = EXCLUDED.summary,
    key_points = EXCLUDED.key_points,
    examples = EXCLUDED.examples,
    practice_questions = EXCLUDED.practice_questions,
    quiz_json = EXCLUDED.quiz_json,
    updated_at = NOW();

-- 3) Point each flagship lesson's notes at the new, fuller AI-content PDF (self-hosted, replacing the older simple notes for these 10 lessons).
UPDATE notes SET title = 'Introduction - AI Notes', pdf_url = '/static/pdfs/mathematics-introduction-ai.pdf'
WHERE lesson_id IN (SELECT l.id FROM lessons l JOIN subjects s ON s.id = l.subject_id WHERE s.name = 'Mathematics' AND l.title = 'Introduction');

INSERT INTO notes (lesson_id, title, pdf_url)
SELECT l.id, 'Introduction - AI Notes', '/static/pdfs/mathematics-introduction-ai.pdf'
FROM lessons l JOIN subjects s ON s.id = l.subject_id
WHERE s.name = 'Mathematics' AND l.title = 'Introduction'
AND NOT EXISTS (SELECT 1 FROM notes n WHERE n.lesson_id = l.id);

UPDATE notes SET title = 'Algebra - AI Notes', pdf_url = '/static/pdfs/mathematics-algebra-ai.pdf'
WHERE lesson_id IN (SELECT l.id FROM lessons l JOIN subjects s ON s.id = l.subject_id WHERE s.name = 'Mathematics' AND l.title = 'Algebra');

INSERT INTO notes (lesson_id, title, pdf_url)
SELECT l.id, 'Algebra - AI Notes', '/static/pdfs/mathematics-algebra-ai.pdf'
FROM lessons l JOIN subjects s ON s.id = l.subject_id
WHERE s.name = 'Mathematics' AND l.title = 'Algebra'
AND NOT EXISTS (SELECT 1 FROM notes n WHERE n.lesson_id = l.id);

UPDATE notes SET title = 'Geometry - AI Notes', pdf_url = '/static/pdfs/mathematics-geometry-ai.pdf'
WHERE lesson_id IN (SELECT l.id FROM lessons l JOIN subjects s ON s.id = l.subject_id WHERE s.name = 'Mathematics' AND l.title = 'Geometry');

INSERT INTO notes (lesson_id, title, pdf_url)
SELECT l.id, 'Geometry - AI Notes', '/static/pdfs/mathematics-geometry-ai.pdf'
FROM lessons l JOIN subjects s ON s.id = l.subject_id
WHERE s.name = 'Mathematics' AND l.title = 'Geometry'
AND NOT EXISTS (SELECT 1 FROM notes n WHERE n.lesson_id = l.id);

UPDATE notes SET title = 'Introduction to Physics - AI Notes', pdf_url = '/static/pdfs/physics-introduction-ai.pdf'
WHERE lesson_id IN (SELECT l.id FROM lessons l JOIN subjects s ON s.id = l.subject_id WHERE s.name = 'Physics' AND l.title = 'Introduction to Physics');

INSERT INTO notes (lesson_id, title, pdf_url)
SELECT l.id, 'Introduction to Physics - AI Notes', '/static/pdfs/physics-introduction-ai.pdf'
FROM lessons l JOIN subjects s ON s.id = l.subject_id
WHERE s.name = 'Physics' AND l.title = 'Introduction to Physics'
AND NOT EXISTS (SELECT 1 FROM notes n WHERE n.lesson_id = l.id);

UPDATE notes SET title = 'Introduction to Chemistry - AI Notes', pdf_url = '/static/pdfs/chemistry-introduction-ai.pdf'
WHERE lesson_id IN (SELECT l.id FROM lessons l JOIN subjects s ON s.id = l.subject_id WHERE s.name = 'Chemistry' AND l.title = 'Introduction to Chemistry');

INSERT INTO notes (lesson_id, title, pdf_url)
SELECT l.id, 'Introduction to Chemistry - AI Notes', '/static/pdfs/chemistry-introduction-ai.pdf'
FROM lessons l JOIN subjects s ON s.id = l.subject_id
WHERE s.name = 'Chemistry' AND l.title = 'Introduction to Chemistry'
AND NOT EXISTS (SELECT 1 FROM notes n WHERE n.lesson_id = l.id);

UPDATE notes SET title = 'Introduction to Biology - AI Notes', pdf_url = '/static/pdfs/biology-introduction-ai.pdf'
WHERE lesson_id IN (SELECT l.id FROM lessons l JOIN subjects s ON s.id = l.subject_id WHERE s.name = 'Biology' AND l.title = 'Introduction to Biology');

INSERT INTO notes (lesson_id, title, pdf_url)
SELECT l.id, 'Introduction to Biology - AI Notes', '/static/pdfs/biology-introduction-ai.pdf'
FROM lessons l JOIN subjects s ON s.id = l.subject_id
WHERE s.name = 'Biology' AND l.title = 'Introduction to Biology'
AND NOT EXISTS (SELECT 1 FROM notes n WHERE n.lesson_id = l.id);

UPDATE notes SET title = 'Ancient Civilizations - AI Notes', pdf_url = '/static/pdfs/history-ancient-civilizations-ai.pdf'
WHERE lesson_id IN (SELECT l.id FROM lessons l JOIN subjects s ON s.id = l.subject_id WHERE s.name = 'History' AND l.title = 'Ancient Civilizations');

INSERT INTO notes (lesson_id, title, pdf_url)
SELECT l.id, 'Ancient Civilizations - AI Notes', '/static/pdfs/history-ancient-civilizations-ai.pdf'
FROM lessons l JOIN subjects s ON s.id = l.subject_id
WHERE s.name = 'History' AND l.title = 'Ancient Civilizations'
AND NOT EXISTS (SELECT 1 FROM notes n WHERE n.lesson_id = l.id);

UPDATE notes SET title = 'Indian Independence Movement - AI Notes', pdf_url = '/static/pdfs/history-indian-independence-ai.pdf'
WHERE lesson_id IN (SELECT l.id FROM lessons l JOIN subjects s ON s.id = l.subject_id WHERE s.name = 'History' AND l.title = 'Indian Independence Movement');

INSERT INTO notes (lesson_id, title, pdf_url)
SELECT l.id, 'Indian Independence Movement - AI Notes', '/static/pdfs/history-indian-independence-ai.pdf'
FROM lessons l JOIN subjects s ON s.id = l.subject_id
WHERE s.name = 'History' AND l.title = 'Indian Independence Movement'
AND NOT EXISTS (SELECT 1 FROM notes n WHERE n.lesson_id = l.id);

UPDATE notes SET title = 'Introduction to Flutter - AI Notes', pdf_url = '/static/pdfs/flutter-introduction-ai.pdf'
WHERE lesson_id IN (SELECT l.id FROM lessons l JOIN subjects s ON s.id = l.subject_id WHERE s.name = 'Flutter' AND l.title = 'Introduction to Flutter');

INSERT INTO notes (lesson_id, title, pdf_url)
SELECT l.id, 'Introduction to Flutter - AI Notes', '/static/pdfs/flutter-introduction-ai.pdf'
FROM lessons l JOIN subjects s ON s.id = l.subject_id
WHERE s.name = 'Flutter' AND l.title = 'Introduction to Flutter'
AND NOT EXISTS (SELECT 1 FROM notes n WHERE n.lesson_id = l.id);

UPDATE notes SET title = 'Go Language Fundamentals - AI Notes', pdf_url = '/static/pdfs/golang-fundamentals-ai.pdf'
WHERE lesson_id IN (SELECT l.id FROM lessons l JOIN subjects s ON s.id = l.subject_id WHERE s.name = 'Golang' AND l.title = 'Go Language Fundamentals');

INSERT INTO notes (lesson_id, title, pdf_url)
SELECT l.id, 'Go Language Fundamentals - AI Notes', '/static/pdfs/golang-fundamentals-ai.pdf'
FROM lessons l JOIN subjects s ON s.id = l.subject_id
WHERE s.name = 'Golang' AND l.title = 'Go Language Fundamentals'
AND NOT EXISTS (SELECT 1 FROM notes n WHERE n.lesson_id = l.id);

-- 4) Educational thumbnails per subject and per flagship lesson.
UPDATE subjects SET thumbnail = '/static/thumbnails/mathematics.png' WHERE name = 'Mathematics';
UPDATE subjects SET thumbnail = '/static/thumbnails/physics.png' WHERE name = 'Physics';
UPDATE subjects SET thumbnail = '/static/thumbnails/chemistry.png' WHERE name = 'Chemistry';
UPDATE subjects SET thumbnail = '/static/thumbnails/biology.png' WHERE name = 'Biology';
UPDATE subjects SET thumbnail = '/static/thumbnails/history.png' WHERE name = 'History';
UPDATE subjects SET thumbnail = '/static/thumbnails/flutter.png' WHERE name = 'Flutter';
UPDATE subjects SET thumbnail = '/static/thumbnails/golang.png' WHERE name = 'Golang';
UPDATE lessons SET thumbnail_url = '/static/thumbnails/mathematics.png'
WHERE id IN (SELECT l.id FROM lessons l JOIN subjects s ON s.id = l.subject_id WHERE s.name = 'Mathematics' AND l.title = 'Introduction');
UPDATE lessons SET thumbnail_url = '/static/thumbnails/mathematics.png'
WHERE id IN (SELECT l.id FROM lessons l JOIN subjects s ON s.id = l.subject_id WHERE s.name = 'Mathematics' AND l.title = 'Algebra');
UPDATE lessons SET thumbnail_url = '/static/thumbnails/mathematics.png'
WHERE id IN (SELECT l.id FROM lessons l JOIN subjects s ON s.id = l.subject_id WHERE s.name = 'Mathematics' AND l.title = 'Geometry');
UPDATE lessons SET thumbnail_url = '/static/thumbnails/physics.png'
WHERE id IN (SELECT l.id FROM lessons l JOIN subjects s ON s.id = l.subject_id WHERE s.name = 'Physics' AND l.title = 'Introduction to Physics');
UPDATE lessons SET thumbnail_url = '/static/thumbnails/chemistry.png'
WHERE id IN (SELECT l.id FROM lessons l JOIN subjects s ON s.id = l.subject_id WHERE s.name = 'Chemistry' AND l.title = 'Introduction to Chemistry');
UPDATE lessons SET thumbnail_url = '/static/thumbnails/biology.png'
WHERE id IN (SELECT l.id FROM lessons l JOIN subjects s ON s.id = l.subject_id WHERE s.name = 'Biology' AND l.title = 'Introduction to Biology');
UPDATE lessons SET thumbnail_url = '/static/thumbnails/history.png'
WHERE id IN (SELECT l.id FROM lessons l JOIN subjects s ON s.id = l.subject_id WHERE s.name = 'History' AND l.title = 'Ancient Civilizations');
UPDATE lessons SET thumbnail_url = '/static/thumbnails/history.png'
WHERE id IN (SELECT l.id FROM lessons l JOIN subjects s ON s.id = l.subject_id WHERE s.name = 'History' AND l.title = 'Indian Independence Movement');
UPDATE lessons SET thumbnail_url = '/static/thumbnails/flutter.png'
WHERE id IN (SELECT l.id FROM lessons l JOIN subjects s ON s.id = l.subject_id WHERE s.name = 'Flutter' AND l.title = 'Introduction to Flutter');
UPDATE lessons SET thumbnail_url = '/static/thumbnails/golang.png'
WHERE id IN (SELECT l.id FROM lessons l JOIN subjects s ON s.id = l.subject_id WHERE s.name = 'Golang' AND l.title = 'Go Language Fundamentals');
