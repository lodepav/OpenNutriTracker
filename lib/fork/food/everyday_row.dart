/// The row a bare family name means where the family has no unspecified
/// row to say so (S75). Every "Egg" and "Pizza" row ties on the title, and
/// the shortest-name key picked the odd ones: "egg" logged "Egg, creamed",
/// "eggs" a yolk, "pizza" "Pizza, no cheese, thin crust" and "cheese pizza"
/// a stuffed crust. The plain whole egg and the restaurant cheese pizza are
/// what the name means when nothing else is said.
bool isEverydayRow(String? name, String query) =>
    name != null && _everyday[query.trim().toLowerCase()] == name;

const _everyday = {
  'egg': 'Egg, whole, raw, fresh',
  'eggs': 'Eggs, Grade A, Large, egg whole',
  'pizza': _cheesePizza,
  'cheese pizza': _cheesePizza,
};

const _cheesePizza =
    'Pizza, cheese, from restaurant or fast food, NS as to type of crust';
