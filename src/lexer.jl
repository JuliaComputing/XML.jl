TAGBEGIN, things of the form of <NAME
TAGEND, of the form of >
TAGCLOSE, of the form of </NAME>
TAGENDANDCLOSE of the form /> (XML only)
ATTRIBUTENAME, of the form of NAME
EQUALSIGN, being precisely =
ATTRIBUTEVALUE, being the value of the exact character string represented by an attribute, regardless of quotes (or even absence of quotes, for legacy HTML). If there are escaped character codes inside the attribute, those code should be converted to their actual character code.
CONTENT, which is the text between TAGENDs and TAGBEGINs. Like ATTRIBUTEVALUES, any escaped characters should be converted, so the CONTENT between <B>foo&lt;bar</B> is converted to the text foo<bar If you want to keep the entity invocations as seperate tokens, you could do that, producing streams of CONTENT and ENTITYINVOCATION tokens between TAGENDs and TAGSTARTs; depends on what your goal is.

TAGBEGIN = r"<[^\s/>]*"
