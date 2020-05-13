---
layout: default
title: "All Categories"
---

# {{ page.title }}

<ul>
  {% for category in site.categories %}
    <li><a href="/{{ category[0] }}/">{{ category[0] }}</a></li>
  {% endfor %}
</ul>
