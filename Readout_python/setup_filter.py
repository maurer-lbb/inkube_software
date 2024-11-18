from setuptools import setup, Extension
from Cython.Build import cythonize
import os
import numpy as np

# extensions = [Extension('filter_in_c', [os.path.join(os.path.dirname(os.path.abspath(__file__)),'filter_in_c.pyx')])]
# # os.path.join(os.path.dirname(os.path.abspath(__file__)),'filter_in_c.pyx')
# setup(
#     name='filter_in_c',
#     ext_modules=cythonize(extensions),
#     zip_safe=False, 
#     include_dirs=[np.get_include()]
# )

# for build call: python setup_filter.py build_ext --inplace


extensions = [
    Extension(
        'inkubeSpike', 
        [os.path.join(os.path.dirname(os.path.abspath(__file__)),'inkubeSpike.pyx')], 
        extra_compile_args=['-fopenmp'],
        extra_link_args=['-fopenmp'])]
# os.path.join(os.path.dirname(os.path.abspath(__file__)),'filter_in_c.pyx')
setup(
    name='inkubeSpike',
    ext_modules=cythonize(extensions, language_level = "3", annotate=True),
    zip_safe=False, 
    include_dirs=[np.get_include()]
)