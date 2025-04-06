from distutils.core import setup

setup(
    name="Notemd",
    version="1.0.0",
    packages=['Notemd'],
    package_data={'Notemd': ['scripts/*.ps1']},
    requires=['requests', 'pathlib', 'regex']
)
