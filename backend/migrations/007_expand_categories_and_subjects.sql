-- Consolidates course categories into a cleaner modern-EdTech structure:
-- Academic (all school subjects) + Competitive Exams (exam prep) +
-- Programming (untouched, unrelated to this request).
--
-- Root cause of "No subjects in this category yet": Physics/Chemistry sat
-- under a separate "Science" category, English sat under "Languages", and
-- a redundant empty "Mathematics" category existed alongside the
-- Mathematics subject that already lives under Academic. Competitive
-- Exams had zero subjects at all.

BEGIN;

-- 1) Move Physics, Chemistry, English into Academic.
UPDATE subjects SET category_id = (SELECT id FROM course_categories WHERE name = 'Academic')
WHERE name IN ('Physics', 'Chemistry', 'English');

-- 2) Delete the now-empty Science and Languages categories, and the
-- redundant empty standalone "Mathematics" category.
DELETE FROM course_categories WHERE name IN ('Science', 'Languages', 'Mathematics');

-- 3) New Academic subjects: Biology, Geography, Social Science,
-- Computer Science, Economics, General Knowledge (2 seed lessons each).
INSERT INTO subjects (category_id, name, description, thumbnail)
SELECT id, 'Biology', 'Life sciences: cells, genetics, and ecosystems.', NULL FROM course_categories WHERE name = 'Academic'
UNION ALL
SELECT id, 'Geography', 'Physical features of the Earth, climate, and human geography.', NULL FROM course_categories WHERE name = 'Academic'
UNION ALL
SELECT id, 'Social Science', 'Civics, society, and how communities are organized and governed.', NULL FROM course_categories WHERE name = 'Academic'
UNION ALL
SELECT id, 'Computer Science', 'Programming basics, data structures, and how computers work.', NULL FROM course_categories WHERE name = 'Academic'
UNION ALL
SELECT id, 'Economics', 'How individuals, businesses, and nations manage resources.', NULL FROM course_categories WHERE name = 'Academic'
UNION ALL
SELECT id, 'General Knowledge', 'Current affairs, notable facts, and general awareness.', NULL FROM course_categories WHERE name = 'Academic';

INSERT INTO lessons (subject_id, title, description, video_url, pdf_url, duration, order_number)
SELECT s.id, 'Introduction to Biology', 'What biology studies and its major branches.', NULL, NULL, 8, 1 FROM subjects s WHERE s.name = 'Biology'
UNION ALL
SELECT s.id, 'Cells and Genetics', 'The basic unit of life and how traits are inherited.', NULL, NULL, 10, 2 FROM subjects s WHERE s.name = 'Biology'
UNION ALL
SELECT s.id, 'Introduction to Geography', 'Earth''s physical features and how geographers study them.', NULL, NULL, 8, 1 FROM subjects s WHERE s.name = 'Geography'
UNION ALL
SELECT s.id, 'Climate and Weather', 'What drives weather patterns and long-term climate.', NULL, NULL, 10, 2 FROM subjects s WHERE s.name = 'Geography'
UNION ALL
SELECT s.id, 'Introduction to Social Science', 'How societies organize, govern, and interact.', NULL, NULL, 8, 1 FROM subjects s WHERE s.name = 'Social Science'
UNION ALL
SELECT s.id, 'Civics and Government', 'How governments are structured and how citizens participate.', NULL, NULL, 10, 2 FROM subjects s WHERE s.name = 'Social Science'
UNION ALL
SELECT s.id, 'Introduction to Computer Science', 'What computer science covers, from hardware to algorithms.', NULL, NULL, 8, 1 FROM subjects s WHERE s.name = 'Computer Science'
UNION ALL
SELECT s.id, 'Programming Fundamentals', 'Variables, loops, and functions - the basics behind any language.', NULL, NULL, 10, 2 FROM subjects s WHERE s.name = 'Computer Science'
UNION ALL
SELECT s.id, 'Introduction to Economics', 'Scarcity, supply and demand, and how markets work.', NULL, NULL, 8, 1 FROM subjects s WHERE s.name = 'Economics'
UNION ALL
SELECT s.id, 'Microeconomics vs Macroeconomics', 'The difference between individual choices and economy-wide trends.', NULL, NULL, 10, 2 FROM subjects s WHERE s.name = 'Economics'
UNION ALL
SELECT s.id, 'Current Affairs Essentials', 'How to stay updated on national and world events.', NULL, NULL, 8, 1 FROM subjects s WHERE s.name = 'General Knowledge'
UNION ALL
SELECT s.id, 'General Awareness: Facts and Figures', 'Commonly tested static GK: geography, history, and science facts.', NULL, NULL, 10, 2 FROM subjects s WHERE s.name = 'General Knowledge';

-- 4) New Competitive Exams subjects (13), 2 seed lessons each.
INSERT INTO subjects (category_id, name, description, thumbnail)
SELECT id, 'UPSC', 'Civil Services Examination preparation: Prelims, Mains, and Interview.', NULL FROM course_categories WHERE name = 'Competitive Exams'
UNION ALL
SELECT id, 'SSC', 'Staff Selection Commission exams: CGL, CHSL, and more.', NULL FROM course_categories WHERE name = 'Competitive Exams'
UNION ALL
SELECT id, 'Banking', 'Bank PO and Clerk exams: IBPS, SBI, and RBI.', NULL FROM course_categories WHERE name = 'Competitive Exams'
UNION ALL
SELECT id, 'Railway', 'RRB exams for technical and non-technical railway posts.', NULL FROM course_categories WHERE name = 'Competitive Exams'
UNION ALL
SELECT id, 'NEET', 'National Eligibility cum Entrance Test for medical admissions.', NULL FROM course_categories WHERE name = 'Competitive Exams'
UNION ALL
SELECT id, 'JEE', 'Joint Entrance Examination for engineering admissions.', NULL FROM course_categories WHERE name = 'Competitive Exams'
UNION ALL
SELECT id, 'CAT', 'Common Admission Test for MBA admissions.', NULL FROM course_categories WHERE name = 'Competitive Exams'
UNION ALL
SELECT id, 'GATE', 'Graduate Aptitude Test in Engineering for postgraduate admissions and PSU jobs.', NULL FROM course_categories WHERE name = 'Competitive Exams'
UNION ALL
SELECT id, 'CUET', 'Common University Entrance Test for undergraduate admissions.', NULL FROM course_categories WHERE name = 'Competitive Exams'
UNION ALL
SELECT id, 'NDA', 'National Defence Academy exam for the Army, Navy, and Air Force wings.', NULL FROM course_categories WHERE name = 'Competitive Exams'
UNION ALL
SELECT id, 'CDS', 'Combined Defence Services exam for officer entry into the armed forces.', NULL FROM course_categories WHERE name = 'Competitive Exams'
UNION ALL
SELECT id, 'State PSC', 'State Public Service Commission exams for state government posts.', NULL FROM course_categories WHERE name = 'Competitive Exams'
UNION ALL
SELECT id, 'Defence Exams', 'Other armed forces entrance exams beyond NDA/CDS.', NULL FROM course_categories WHERE name = 'Competitive Exams';

INSERT INTO lessons (subject_id, title, description, video_url, pdf_url, duration, order_number)
SELECT s.id, 'UPSC Exam Overview', 'Exam pattern, stages, and how the selection process works.', NULL, NULL, 10, 1 FROM subjects s WHERE s.name = 'UPSC'
UNION ALL
SELECT s.id, 'UPSC Key Preparation Areas', 'Core subjects and strategy for Prelims and Mains.', NULL, NULL, 12, 2 FROM subjects s WHERE s.name = 'UPSC'
UNION ALL
SELECT s.id, 'SSC Exam Overview', 'CGL, CHSL, and other SSC exam patterns explained.', NULL, NULL, 10, 1 FROM subjects s WHERE s.name = 'SSC'
UNION ALL
SELECT s.id, 'SSC Key Preparation Areas', 'Quant, reasoning, English, and general awareness focus areas.', NULL, NULL, 10, 2 FROM subjects s WHERE s.name = 'SSC'
UNION ALL
SELECT s.id, 'Banking Exam Overview', 'IBPS, SBI PO/Clerk exam structure and eligibility.', NULL, NULL, 10, 1 FROM subjects s WHERE s.name = 'Banking'
UNION ALL
SELECT s.id, 'Banking Key Preparation Areas', 'Quantitative aptitude, reasoning, and banking awareness.', NULL, NULL, 10, 2 FROM subjects s WHERE s.name = 'Banking'
UNION ALL
SELECT s.id, 'Railway Exam Overview', 'RRB NTPC and Group D exam patterns explained.', NULL, NULL, 10, 1 FROM subjects s WHERE s.name = 'Railway'
UNION ALL
SELECT s.id, 'Railway Key Preparation Areas', 'Maths, general science, and general awareness focus areas.', NULL, NULL, 10, 2 FROM subjects s WHERE s.name = 'Railway'
UNION ALL
SELECT s.id, 'NEET Exam Overview', 'Exam pattern and syllabus weightage across Physics, Chemistry, and Biology.', NULL, NULL, 10, 1 FROM subjects s WHERE s.name = 'NEET'
UNION ALL
SELECT s.id, 'NEET Key Preparation Areas', 'High-yield NCERT topics and how to prioritize revision.', NULL, NULL, 12, 2 FROM subjects s WHERE s.name = 'NEET'
UNION ALL
SELECT s.id, 'JEE Exam Overview', 'JEE Main vs Advanced, exam pattern, and eligibility.', NULL, NULL, 10, 1 FROM subjects s WHERE s.name = 'JEE'
UNION ALL
SELECT s.id, 'JEE Key Preparation Areas', 'Physics, Chemistry, and Maths weightage and strategy.', NULL, NULL, 12, 2 FROM subjects s WHERE s.name = 'JEE'
UNION ALL
SELECT s.id, 'CAT Exam Overview', 'Exam sections, scoring, and percentile-based selection.', NULL, NULL, 10, 1 FROM subjects s WHERE s.name = 'CAT'
UNION ALL
SELECT s.id, 'CAT Key Preparation Areas', 'Quant, Verbal Ability, and Data Interpretation focus areas.', NULL, NULL, 10, 2 FROM subjects s WHERE s.name = 'CAT'
UNION ALL
SELECT s.id, 'GATE Exam Overview', 'Exam pattern, scoring, and how GATE scores are used.', NULL, NULL, 10, 1 FROM subjects s WHERE s.name = 'GATE'
UNION ALL
SELECT s.id, 'GATE Key Preparation Areas', 'Core engineering subjects and aptitude section strategy.', NULL, NULL, 12, 2 FROM subjects s WHERE s.name = 'GATE'
UNION ALL
SELECT s.id, 'CUET Exam Overview', 'Exam structure for domain subjects, languages, and general test.', NULL, NULL, 10, 1 FROM subjects s WHERE s.name = 'CUET'
UNION ALL
SELECT s.id, 'CUET Key Preparation Areas', 'Choosing domain subjects and general test preparation.', NULL, NULL, 10, 2 FROM subjects s WHERE s.name = 'CUET'
UNION ALL
SELECT s.id, 'NDA Exam Overview', 'Written exam plus SSB interview process explained.', NULL, NULL, 10, 1 FROM subjects s WHERE s.name = 'NDA'
UNION ALL
SELECT s.id, 'NDA Key Preparation Areas', 'Maths and General Ability Test focus areas.', NULL, NULL, 10, 2 FROM subjects s WHERE s.name = 'NDA'
UNION ALL
SELECT s.id, 'CDS Exam Overview', 'Written exam plus SSB interview for officer entry.', NULL, NULL, 10, 1 FROM subjects s WHERE s.name = 'CDS'
UNION ALL
SELECT s.id, 'CDS Key Preparation Areas', 'English, GK, and Elementary Mathematics focus areas.', NULL, NULL, 10, 2 FROM subjects s WHERE s.name = 'CDS'
UNION ALL
SELECT s.id, 'State PSC Exam Overview', 'How state PSC exams differ from UPSC, state to state.', NULL, NULL, 10, 1 FROM subjects s WHERE s.name = 'State PSC'
UNION ALL
SELECT s.id, 'State PSC Key Preparation Areas', 'State-specific GK plus general aptitude focus areas.', NULL, NULL, 10, 2 FROM subjects s WHERE s.name = 'State PSC'
UNION ALL
SELECT s.id, 'Defence Exams Overview', 'Other entry routes into the armed forces beyond NDA/CDS.', NULL, NULL, 10, 1 FROM subjects s WHERE s.name = 'Defence Exams'
UNION ALL
SELECT s.id, 'Defence Exams Key Preparation Areas', 'Physical fitness, written test, and interview preparation.', NULL, NULL, 10, 2 FROM subjects s WHERE s.name = 'Defence Exams';

COMMIT;
