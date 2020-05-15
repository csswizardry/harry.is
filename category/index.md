---
title: "All Categories"
layout: default
---

# {{ page.title }}

<ul>
  {% for category in site.categories %}
    <li><a href="/{{ category[0] }}/">{{ category[0] }}</a></li>
  {% endfor %}
</ul>
