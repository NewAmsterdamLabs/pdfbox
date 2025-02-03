Apache PdfBox has built relatively strong ligature support in version 3
We managed to add some more ligatures to support that are available in version 3.0.2
Unfortunately, we have a special use case that needs time to implement correctly in Apache PdfBox.
We have our own implementation that works for Zola use cases as we work with Latin characters.
If you need to update PdfBox to a new version, please check this commit:
https://github.com/NewAmsterdamLabs/pdfbox/commit/b34ce867a3f7bae024de30908d86238d3160ff96

You may have to cherry-pick that commit or check for any changes made by Apache contributors.
```