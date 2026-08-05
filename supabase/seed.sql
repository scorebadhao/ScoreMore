-- ScoreMore initial dynamic configuration.
-- Safe to rerun after `supabase db reset`.

insert into public.boards (board_id, board_name, board_code, description, status, sort_order)
values ('GSSSB', 'Gujarat Subordinate Service Selection Board', 'GSSSB', 'Initial ScoreMore public board scope.', 'ACTIVE', 1)
on conflict (board_id) do update set
  board_name = excluded.board_name,
  description = excluded.description,
  status = excluded.status,
  sort_order = excluded.sort_order;

insert into public.exams (exam_id, board_id, exam_name, exam_code, description, status, sort_order)
values ('CCE', 'GSSSB', 'Combined Competitive Examination (CCE)', 'CCE', 'Initial ScoreMore public exam scope.', 'ACTIVE', 1)
on conflict (exam_id) do update set
  exam_name = excluded.exam_name,
  description = excluded.description,
  status = excluded.status,
  sort_order = excluded.sort_order;

insert into public.subjects (subject_id, exam_id, subject_name, subject_code, description, status, sort_order)
values
  ('REASONING', 'CCE', 'Reasoning', 'REASONING', 'Reasoning and logical ability.', 'ACTIVE', 1),
  ('QUANTITATIVE_APTITUDE', 'CCE', 'Quantitative Aptitude', 'QUANT', 'Mathematics and quantitative aptitude.', 'ACTIVE', 2),
  ('ENGLISH', 'CCE', 'English', 'ENGLISH', 'English language section.', 'ACTIVE', 3),
  ('GUJARATI', 'CCE', 'Gujarati', 'GUJARATI', 'Gujarati language section.', 'ACTIVE', 4)
on conflict (subject_id) do update set
  subject_name = excluded.subject_name,
  description = excluded.description,
  status = excluded.status,
  sort_order = excluded.sort_order;

insert into public.app_settings (setting_key, setting_value, description, is_public)
values
  ('app_name', 'ScoreMore', 'Public product name.', true),
  ('app_tagline', 'Prepare smarter', 'Short brand tagline.', true),
  ('scope_badge', 'GSSSB CCE', 'Current public exam scope.', true),
  ('hero_title', 'Prepare Smarter for GSSSB CCE', 'Landing page primary heading.', true),
  ('hero_subtitle', 'અસલ PYQ, વિભાગવાર પ્રેક્ટિસ, ફુલ ટેસ્ટ અને સ્માર્ટ એનાલિટિક્સ સાથે તૈયારી કરો.', 'Landing page Gujarati support line.', true)
on conflict (setting_key) do update set
  setting_value = excluded.setting_value,
  description = excluded.description,
  is_public = excluded.is_public,
  updated_at = now();


-- Phase 3E canonical GSSSB CCE topic catalogue.
insert into public.topics (topic_id, subject_id, topic_name, topic_code, description, sort_order)
values
  ('REASONING-NUMBER-SERIES', 'REASONING', 'Number Series', 'NUMBER_SERIES', 'Number patterns, missing terms and sequence logic.', 10),
  ('REASONING-ALPHABET-SERIES', 'REASONING', 'Alphabet Series', 'ALPHABET_SERIES', 'Alphabet and alphanumeric sequence questions.', 20),
  ('REASONING-FIGURE-SERIES', 'REASONING', 'Figure Series', 'FIGURE_SERIES', 'Non-verbal figure sequence and next-figure questions.', 30),
  ('REASONING-FIGURE-ANALOGY', 'REASONING', 'Figure Analogy', 'FIGURE_ANALOGY', 'Analogy relationships represented with figures.', 40),
  ('REASONING-FIGURE-CLASSIFICATION', 'REASONING', 'Figure Classification', 'FIGURE_CLASSIFICATION', 'Odd figure and figure classification questions.', 50),
  ('REASONING-CODING-DECODING', 'REASONING', 'Coding and Decoding', 'CODING_DECODING', 'Letter, number and symbol coding-decoding.', 60),
  ('REASONING-BLOOD-RELATION', 'REASONING', 'Blood Relation', 'BLOOD_RELATION', 'Family and blood-relation reasoning.', 70),
  ('REASONING-DIRECTION-SENSE', 'REASONING', 'Direction Sense', 'DIRECTION_SENSE', 'Direction, distance and movement reasoning.', 80),
  ('REASONING-RANKING-ORDER', 'REASONING', 'Ranking and Order', 'RANKING_ORDER', 'Position, rank and order based reasoning.', 90),
  ('REASONING-SEATING-ARRANGEMENT', 'REASONING', 'Seating Arrangement', 'SEATING_ARRANGEMENT', 'Linear and circular arrangement problems.', 100),
  ('REASONING-PUZZLE', 'REASONING', 'Logical Puzzle', 'PUZZLE', 'Multi-condition logical puzzle questions.', 110),
  ('REASONING-ANALOGY', 'REASONING', 'Analogy', 'ANALOGY', 'Word, number and logical analogy.', 120),
  ('REASONING-CLASSIFICATION', 'REASONING', 'Classification', 'CLASSIFICATION', 'Classification and odd-one-out reasoning.', 130),
  ('REASONING-MATHEMATICAL-OPERATIONS', 'REASONING', 'Mathematical Operations', 'MATHEMATICAL_OPERATIONS', 'Symbol substitution and operator based reasoning.', 140),
  ('REASONING-MISSING-NUMBER', 'REASONING', 'Missing Number', 'MISSING_NUMBER', 'Missing value in diagrams or numeric patterns.', 150),
  ('REASONING-SYLLOGISM', 'REASONING', 'Syllogism', 'SYLLOGISM', 'Logical conclusions from statements.', 160),
  ('REASONING-STATEMENT-CONCLUSION', 'REASONING', 'Statement and Conclusion', 'STATEMENT_CONCLUSION', 'Conclusion, inference and statement logic.', 170),
  ('REASONING-DATA-SUFFICIENCY', 'REASONING', 'Data Sufficiency', 'DATA_SUFFICIENCY', 'Determine whether the supplied statements are sufficient.', 180),
  ('REASONING-VENN-DIAGRAM', 'REASONING', 'Venn Diagram', 'VENN_DIAGRAM', 'Set relationships and Venn-diagram reasoning.', 190),
  ('REASONING-DATA-INTERPRETATION', 'REASONING', 'Data Interpretation', 'DATA_INTERPRETATION', 'Tables, line graphs and chart interpretation.', 200),
  ('REASONING-FIGURE-COUNTING', 'REASONING', 'Figure Counting', 'FIGURE_COUNTING', 'Count shapes or components in complex figures.', 210),
  ('REASONING-EMBEDDED-FIGURE', 'REASONING', 'Embedded Figure', 'EMBEDDED_FIGURE', 'Find a simple figure hidden in a complex figure.', 220),
  ('REASONING-PAPER-FOLDING-CUTTING', 'REASONING', 'Paper Folding and Cutting', 'PAPER_FOLDING_CUTTING', 'Paper folding, cutting and hole-punch patterns.', 230),
  ('REASONING-MIRROR-WATER-IMAGE', 'REASONING', 'Mirror and Water Image', 'MIRROR_WATER_IMAGE', 'Mirror-image and water-image reasoning.', 240),
  ('REASONING-CUBE-DICE', 'REASONING', 'Cube and Dice', 'CUBE_DICE', 'Cube, dice and spatial-face relationships.', 250),
  ('REASONING-NON-VERBAL', 'REASONING', 'Non-Verbal Reasoning', 'NON_VERBAL_REASONING', 'Other diagrammatic and spatial reasoning.', 260),
  ('QUANT-NUMBER-SYSTEM', 'QUANTITATIVE_APTITUDE', 'Number System', 'NUMBER_SYSTEM', 'Properties and operations involving numbers.', 10),
  ('QUANT-SIMPLIFICATION', 'QUANTITATIVE_APTITUDE', 'Simplification', 'SIMPLIFICATION', 'Arithmetic simplification and approximation.', 20),
  ('QUANT-HCF-LCM', 'QUANTITATIVE_APTITUDE', 'HCF and LCM', 'HCF_LCM', 'Highest common factor and least common multiple.', 30),
  ('QUANT-RATIO-PROPORTION', 'QUANTITATIVE_APTITUDE', 'Ratio and Proportion', 'RATIO_PROPORTION', 'Ratio, proportion and variation.', 40),
  ('QUANT-PERCENTAGE', 'QUANTITATIVE_APTITUDE', 'Percentage', 'PERCENTAGE', 'Percentage calculations and applications.', 50),
  ('QUANT-PROFIT-LOSS-DISCOUNT', 'QUANTITATIVE_APTITUDE', 'Profit, Loss and Discount', 'PROFIT_LOSS_DISCOUNT', 'Commercial arithmetic involving profit, loss and discount.', 60),
  ('QUANT-SIMPLE-INTEREST', 'QUANTITATIVE_APTITUDE', 'Simple Interest', 'SIMPLE_INTEREST', 'Simple-interest calculations.', 70),
  ('QUANT-COMPOUND-INTEREST', 'QUANTITATIVE_APTITUDE', 'Compound Interest', 'COMPOUND_INTEREST', 'Compound-interest and growth calculations.', 80),
  ('QUANT-AVERAGE', 'QUANTITATIVE_APTITUDE', 'Average', 'AVERAGE', 'Arithmetic mean and weighted average.', 90),
  ('QUANT-AGE-PROBLEMS', 'QUANTITATIVE_APTITUDE', 'Age Problems', 'AGE_PROBLEMS', 'Present, past and future age relationships.', 100),
  ('QUANT-TIME-WORK', 'QUANTITATIVE_APTITUDE', 'Time and Work', 'TIME_WORK', 'Work rates and combined work.', 110),
  ('QUANT-PIPES-CISTERNS', 'QUANTITATIVE_APTITUDE', 'Pipes and Cisterns', 'PIPES_CISTERNS', 'Filling and emptying rate problems.', 120),
  ('QUANT-TIME-SPEED-DISTANCE', 'QUANTITATIVE_APTITUDE', 'Time, Speed and Distance', 'TIME_SPEED_DISTANCE', 'Motion, distance and relative speed.', 130),
  ('QUANT-TRAINS', 'QUANTITATIVE_APTITUDE', 'Trains', 'TRAINS', 'Train speed and crossing problems.', 140),
  ('QUANT-BOATS-STREAMS', 'QUANTITATIVE_APTITUDE', 'Boats and Streams', 'BOATS_STREAMS', 'Upstream and downstream motion.', 150),
  ('QUANT-MENSURATION', 'QUANTITATIVE_APTITUDE', 'Mensuration', 'MENSURATION', 'Perimeter, area, surface area and volume.', 160),
  ('QUANT-ALGEBRA', 'QUANTITATIVE_APTITUDE', 'Algebra', 'ALGEBRA', 'Algebraic expressions and equations.', 170),
  ('QUANT-GEOMETRY', 'QUANTITATIVE_APTITUDE', 'Geometry', 'GEOMETRY', 'Plane geometry and geometric properties.', 180),
  ('QUANT-DATA-INTERPRETATION', 'QUANTITATIVE_APTITUDE', 'Data Interpretation', 'DATA_INTERPRETATION', 'Tables, charts and graphs for quantitative analysis.', 190),
  ('QUANT-MIXTURE-ALLIGATION', 'QUANTITATIVE_APTITUDE', 'Mixture and Alligation', 'MIXTURE_ALLIGATION', 'Mixture, concentration and alligation.', 200),
  ('QUANT-PARTNERSHIP', 'QUANTITATIVE_APTITUDE', 'Partnership', 'PARTNERSHIP', 'Investment ratio and partnership profit.', 210),
  ('QUANT-CALENDAR', 'QUANTITATIVE_APTITUDE', 'Calendar', 'CALENDAR', 'Date, day and calendar arithmetic.', 220),
  ('QUANT-CLOCK', 'QUANTITATIVE_APTITUDE', 'Clock', 'CLOCK', 'Clock angle and time relationships.', 230),
  ('QUANT-PROBABILITY', 'QUANTITATIVE_APTITUDE', 'Probability', 'PROBABILITY', 'Elementary probability.', 240),
  ('QUANT-PERMUTATION-COMBINATION', 'QUANTITATIVE_APTITUDE', 'Permutation and Combination', 'PERMUTATION_COMBINATION', 'Counting arrangements and selections.', 250),
  ('QUANT-SERIES', 'QUANTITATIVE_APTITUDE', 'Arithmetic and Number Series', 'SERIES', 'Series sums and quantitative sequence questions.', 260),
  ('ENGLISH-SYNONYMS', 'ENGLISH', 'Synonyms', 'SYNONYMS', 'Words with similar meanings.', 10),
  ('ENGLISH-ANTONYMS', 'ENGLISH', 'Antonyms', 'ANTONYMS', 'Words with opposite meanings.', 20),
  ('ENGLISH-ONE-WORD-SUBSTITUTION', 'ENGLISH', 'One Word Substitution', 'ONE_WORD_SUBSTITUTION', 'Single-word substitutions for phrases.', 30),
  ('ENGLISH-IDIOMS-PHRASES', 'ENGLISH', 'Idioms and Phrases', 'IDIOMS_PHRASES', 'Meaning and usage of idiomatic expressions.', 40),
  ('ENGLISH-PREPOSITIONS', 'ENGLISH', 'Prepositions', 'PREPOSITIONS', 'Correct use of prepositions.', 50),
  ('ENGLISH-ARTICLES', 'ENGLISH', 'Articles', 'ARTICLES', 'Use of a, an and the.', 60),
  ('ENGLISH-TENSES', 'ENGLISH', 'Tenses', 'TENSES', 'Verb tense usage.', 70),
  ('ENGLISH-VERB-FORMS', 'ENGLISH', 'Verb Forms', 'VERB_FORMS', 'Inflection and correct verb forms.', 80),
  ('ENGLISH-SUBJECT-VERB-AGREEMENT', 'ENGLISH', 'Subject–Verb Agreement', 'SUBJECT_VERB_AGREEMENT', 'Agreement between subject and verb.', 90),
  ('ENGLISH-FILL-BLANKS', 'ENGLISH', 'Fill in the Blanks', 'FILL_IN_THE_BLANKS', 'Contextual grammar and vocabulary blanks.', 100),
  ('ENGLISH-SENTENCE-ARRANGEMENT', 'ENGLISH', 'Sentence Arrangement', 'SENTENCE_ARRANGEMENT', 'Rearrangement of sentences or clauses.', 110),
  ('ENGLISH-ERROR-DETECTION', 'ENGLISH', 'Error Detection', 'ERROR_DETECTION', 'Identify grammatical or usage errors.', 120),
  ('ENGLISH-READING-COMPREHENSION', 'ENGLISH', 'Reading Comprehension', 'READING_COMPREHENSION', 'Passage-based comprehension questions.', 130),
  ('ENGLISH-TRANSLATION', 'ENGLISH', 'Translation', 'TRANSLATION', 'English–Gujarati translation questions.', 140),
  ('ENGLISH-SPELLING', 'ENGLISH', 'Spelling', 'SPELLING', 'Correct spelling and orthography.', 150),
  ('ENGLISH-ACTIVE-PASSIVE', 'ENGLISH', 'Active and Passive Voice', 'ACTIVE_PASSIVE', 'Voice transformation and usage.', 160),
  ('ENGLISH-DIRECT-INDIRECT', 'ENGLISH', 'Direct and Indirect Speech', 'DIRECT_INDIRECT', 'Reported speech transformation.', 170),
  ('ENGLISH-VOCABULARY', 'ENGLISH', 'Vocabulary', 'VOCABULARY', 'General vocabulary questions.', 180),
  ('GUJARATI-SPELLING', 'GUJARATI', 'ગુજરાતી જોડણી', 'GUJARATI_SPELLING', 'ગુજરાતી શબ્દોની સાચી જોડણી.', 10),
  ('GUJARATI-SYNONYMS', 'GUJARATI', 'સમાનાર્થી શબ્દો', 'GUJARATI_SYNONYMS', 'ગુજરાતી સમાનાર્થી શબ્દો.', 20),
  ('GUJARATI-ANTONYMS', 'GUJARATI', 'વિરુદ્ધાર્થી શબ્દો', 'GUJARATI_ANTONYMS', 'ગુજરાતી વિરુદ્ધાર્થી શબ્દો.', 30),
  ('GUJARATI-IDIOMS', 'GUJARATI', 'રૂઢિપ્રયોગ', 'GUJARATI_IDIOMS', 'ગુજરાતી રૂઢિપ્રયોગ અને અર્થ.', 40),
  ('GUJARATI-PROVERBS', 'GUJARATI', 'કહેવતો', 'GUJARATI_PROVERBS', 'ગુજરાતી કહેવતો અને અર્થ.', 50),
  ('GUJARATI-GRAMMAR', 'GUJARATI', 'ગુજરાતી વ્યાકરણ', 'GUJARATI_GRAMMAR', 'સામાન્ય ગુજરાતી વ્યાકરણ.', 60),
  ('GUJARATI-SANDHI', 'GUJARATI', 'સંધિ', 'GUJARATI_SANDHI', 'સંધિ અને સંધિવિચ્છેદ.', 70),
  ('GUJARATI-SAMAS', 'GUJARATI', 'સમાસ', 'GUJARATI_SAMAS', 'સમાસ અને સમાસવિગ્રહ.', 80),
  ('GUJARATI-ALANKAR', 'GUJARATI', 'અલંકાર', 'GUJARATI_ALANKAR', 'ગુજરાતી અલંકાર.', 90),
  ('GUJARATI-CHHAND', 'GUJARATI', 'છંદ', 'GUJARATI_CHHAND', 'ગુજરાતી છંદ.', 100),
  ('GUJARATI-VOCABULARY', 'GUJARATI', 'શબ્દભંડોળ', 'GUJARATI_VOCABULARY', 'ગુજરાતી શબ્દભંડોળ અને અર્થ.', 110),
  ('GUJARATI-SENTENCE-CORRECTION', 'GUJARATI', 'વાક્યશુદ્ધિ', 'GUJARATI_SENTENCE_CORRECTION', 'ગુજરાતી વાક્યમાં ભાષાશુદ્ધિ.', 120),
  ('GUJARATI-TRANSLATION', 'GUJARATI', 'અનુવાદ', 'GUJARATI_TRANSLATION', 'ગુજરાતી અનુવાદ આધારિત પ્રશ્નો.', 130)
on conflict (topic_id) do update set
  subject_id = excluded.subject_id,
  topic_name = excluded.topic_name,
  topic_code = excluded.topic_code,
  description = excluded.description,
  status = 'ACTIVE',
  sort_order = excluded.sort_order,
  updated_at = now();
