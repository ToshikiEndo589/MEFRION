import unittest
from scripts.filter_pexels_dog_cat import eligible
from scripts.collect_pexels_assets import QUERIES

class DogCatFilterTests(unittest.TestCase):
    def test_collection_queries_only_dog_cat(self):
        self.assertEqual({species for species,query in QUERIES}, {'dog','cat'})

    def test_dog_cat_descriptions_retained(self):
        for species,description in [('dog','A cute puppy sleeping'),('dog','Golden retriever portrait'),
                                    ('cat','A kitten on a sofa'),('cat','A tabby resting')]:
            self.assertTrue(eligible({'species_hint':species,'alt':description})[0])

    def test_other_categories_and_mixed_animals_excluded(self):
        for species,description in [('bird','A parrot'),('rabbit','White rabbit'),
                                    ('cat','A cat with a rabbit'),('dog','A dog and horse')]:
            self.assertFalse(eligible({'species_hint':species,'alt':description})[0])

    def test_unknown_or_misleading_description_excluded(self):
        for description in ('','A beautiful landscape','A tiger portrait','A cattle farm','Catfish in water'):
            self.assertFalse(eligible({'species_hint':'cat','alt':description})[0])

if __name__=='__main__':
    unittest.main()
